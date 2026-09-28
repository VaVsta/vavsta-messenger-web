#!/usr/bin/env bash
# Релиз веб-части VaVsta: сборка -> (по --deploy) выкладка на chat.vavsta.ru.
#
# Ключевое: файл `version` НЕ пишется руками — его генерирует сам webpack
# (VersionFilePlugin, apps/web/webpack.config.ts) из apps/web/package.json.
# То есть версия в бандле и в /version всегда совпадают by construction:
# поднял версию в package.json → собрал → /var/www/element/version поехал вместе
# с бандлами. Рассинхрон (в бандле 1.12.27, в /version 1.12.26) невозможен.
#
# Использование:
#   ./deploy/release-web.sh              # собрать локально, ничего не выкладывать
#   ./deploy/release-web.sh --deploy     # собрать и выложить на сервер
#   ./deploy/release-web.sh --bump patch # поднять версию (patch/minor/major) перед сборкой
#   ./deploy/release-web.sh --deploy --bump patch
#
# SSH: ключ ~/.ssh/id_ed25519 под паролем «Lala101201», поэтому нужен ssh-agent.
# Скрипт НЕ подставляет пароль и не спросит его — если agent не запущен, сначала
# подними его (см. AGENTS/память) либо правь SSH= в этом файле под свой способ.
#
# Что НЕ трогает скрипт (и не удаляет при --delete):
#   config.json, config.chat.vavsta.ru.json — серверная конфигурация Element
#   vavsta-messenger/                        — OTA Android (APK + version.json)
#   .well-known/                             — если появится
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEBAPP="$REPO/apps/web/webapp"
PKG_WEB="$REPO/apps/web/package.json"
HOST="chat.vavsta.ru"
WEBROOT="/var/www/element"
BASE_URL="https://$HOST"
DEPLOY=0
BUMP=""

# Ключ под паролем — нужен агент. Если агента нет, скрипт скажет об этом и выйдет,
# а не будет молча висеть на запросе пароля.
if ! ssh-add -l >/dev/null 2>&1; then
    if ! SSH_AUTH_SOCK=/tmp/opencode/agent.sock ssh-add -l >/dev/null 2>&1; then
        echo "!! нет ssh-agent с ключом для $HOST." >&2
        echo "   Подними агент (нужен для sudo/ssh без пароля) и повтори." >&2
        exit 1
    fi
    export SSH_AUTH_SOCK=/tmp/opencode/agent.sock
fi
SSH=(ssh -o IdentitiesOnly=yes -o BatchMode=yes)

# Что на сервере живёт само по себе и не должно попадать под --delete
PROTECTED=(
    "/config.json"
    "/config.chat.vavsta.ru.json"
    "/vavsta-messenger/"
    "/.well-known/"
)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --deploy) DEPLOY=1; shift ;;
        --bump) BUMP="${2:?--bump требует аргумент: patch|minor|major}"; shift 2 ;;
        --host) HOST="${2:?}"; shift 2 ;;
        -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
        *) echo "неизвестный аргумент: $1" >&2; exit 1 ;;
    esac
done

cd "$REPO"

# --- 1. Версия ---------------------------------------------------------------
if [[ -n "$BUMP" ]]; then
    current="$(node -p "require('$PKG_WEB').version")"
    new="$(node -e "
        const [maj, min, pat] = process.argv[1].split('.').map(Number);
        const b = process.argv[2];
        const out = b === 'major' ? [maj+1,0,0] : b === 'minor' ? [maj,min+1,0] : [maj,min,pat+1];
        console.log(out.join('.'));
    " "$current" "$BUMP")"
    echo "==> Версия: $current -> $new"
    cp "$PKG_WEB" /tmp/opencode/apps-web-package.json.bak-$(date +%Y%m%d-%H%M%S)
    node -e "
        const fs = require('fs');
        const p = '$PKG_WEB';
        const raw = fs.readFileSync(p, 'utf8');
        fs.writeFileSync(p, raw.replace(/\"version\": \"${current}\"/, '\"version\": \"${new}\"'));
    "
    if [[ "$(node -p "require('$PKG_WEB').version")" != "$new" ]]; then
        echo "!! не удалось поднять версию в $PKG_WEB" >&2
        exit 1
    fi
    # changelog.json должен соответствовать новой версии, иначе тост будет врать
    if [[ -f "$REPO/apps/web/res/changelog.json" ]]; then
        node -e "
            const fs = require('fs');
            const p = '$REPO/apps/web/res/changelog.json';
            const d = JSON.parse(fs.readFileSync(p, 'utf8'));
            d.version = '${new}';
            d.date = new Date().toISOString().slice(0, 10);
            fs.writeFileSync(p, JSON.stringify(d, null, 4) + '\n');
            console.log('==> changelog.json: version ->', d.version, ', date ->', d.date);
        "
    fi
fi

VERSION="$(node -p "require('$PKG_WEB').version")"
echo "==> Версия в apps/web/package.json: $VERSION"

# --- 2. Сборка ---------------------------------------------------------------
echo "==> Сборка (production)"
build_started="$(date +%s)"
rm -rf "$WEBAPP/bundles"
pnpm --filter element-web build

# --- 3. Проверки локально ----------------------------------------------------
[[ -f "$WEBAPP/version" ]] || { echo "!! нет $WEBAPP/version" >&2; exit 1; }
built="$(tr -d '\n' < "$WEBAPP/version")"
if [[ "$built" != "$VERSION" ]]; then
    echo "!! сборка вернула версию $built, ожидалась $VERSION" >&2
    exit 1
fi
[[ -f "$WEBAPP/index.html" ]] || { echo "!! нет index.html" >&2; exit 1; }
if [[ -f "$REPO/apps/web/res/changelog.json" ]]; then
    [[ -f "$WEBAPP/changelog.json" ]] || { echo "!! changelog.json не попал в сборку" >&2; exit 1; }
    node -e "JSON.parse(require('fs').readFileSync('$WEBAPP/changelog.json'))" \
        || { echo "!! changelog.json невалидный JSON" >&2; exit 1; }
fi
bundle="$(ls -1 "$WEBAPP/bundles" | head -1)"
bundle_mtime="$(stat -c %Y "$WEBAPP/bundles/$bundle")"
if [[ "$bundle_mtime" -le "$build_started" ]]; then
    echo "!! бандл $bundle не пересобрался (mtime $bundle_mtime <= старт сборки $build_started)" >&2
    exit 1
fi
echo "==> Сборка ок: bundle=$bundle version=$built changelog=$( [[ -f $WEBAPP/changelog.json ]] && echo есть || echo нет )"

if [[ "$DEPLOY" != "1" ]]; then
    echo
    echo "==> Собрано, НЕ выложено. Дальше:"
    echo "    ./deploy/release-web.sh --deploy"
    exit 0
fi

# --- 4. Выкладка -------------------------------------------------------------
# rsync --delete с --exclude: исключённые файлы на приёмнике НЕ удаляются,
# поэтому серверные config.json / config.chat.vavsta.ru.json / vavsta-messenger/
# переживают выкладку. Бэкап index.html+version+config — на всякий случай.
echo "==> Бэкап на сервере"
"${SSH[@]}" "root@$HOST" "set -e
    BK=/var/backups/element-web/\$(date +%Y%m%d-%H%M%S); mkdir -p \$BK
    cd '$WEBROOT'
    cp -a index.html version config.json \$BK/ 2>/dev/null || true
    [ -f changelog.json ] && cp -a changelog.json \$BK/ || true
    echo \$BK > /var/backups/element-web/.last
    echo '    бэкап:' \$BK
"

rsync_opts=(
    --archive --compress --delete --human-readable --stats
    --exclude=".DS_Store"
)
for p in "${PROTECTED[@]}"; do
    rsync_opts+=(--exclude="$p")
done

echo "==> rsync $WEBAPP/ -> root@$HOST:$WEBROOT/"
rsync "${rsync_opts[@]}" -e "ssh -o IdentitiesOnly=yes -o BatchMode=yes" "$WEBAPP/" "root@$HOST:$WEBROOT/"

# --- 5. Чистка старых бандлов ------------------------------------------------
# Оставляем текущий и предыдущий: клиент, у которого в кеше лежит старый
# index.html, после выкладки ещё какое-то время дёргает старые бандлы.
echo "==> Старые бандлы (оставляем текущий + предыдущий)"
"${SSH[@]}" "root@$HOST" "set -e
    cd '$WEBROOT'
    cur=\$(grep -o 'bundles/[0-9a-f]\\{20\\}' '$WEBROOT/index.html' 2>/dev/null | head -1 | cut -d/ -f2)
    [ -z \"\$cur\" ] && cur=\$(ls -1dt '$WEBROOT'/bundles/*/ 2>/dev/null | head -1 | xargs -r basename)
    echo \"    текущий: \$cur\"
    ls -1dt '$WEBROOT'/bundles/*/ 2>/dev/null | tail -n +3 | while read -r d; do
        echo \"    удаляю \$d\"
        rm -rf \"\$d\"
    done
    chown -R www-data:www-data '$WEBROOT'
"

# --- 6. Проверки после выкладки ---------------------------------------------
echo "==> Проверка прода"
fail=0
check() { # url, ожидание
    local got
    got="$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' "$1" || echo 000)"
    if [[ "$got" == "$2" ]]; then
        printf '    %-42s %s ok\n' "${1#$BASE_URL}" "$got"
    else
        printf '    %-42s %s FAIL (ожидалось %s)\n' "${1#$BASE_URL}" "$got" "$2"
        fail=1
    fi
}
check "$BASE_URL/" 200
check "$BASE_URL/version" 200
check "$BASE_URL/index.html" 200
check "$BASE_URL/changelog.json" 200
check "$BASE_URL/mobile_guide/" 200
check "$BASE_URL/vavsta-messenger/version.json" 200

served="$(curl -sS --max-time 15 "$BASE_URL/version" | tr -d '\n[:space:]')"
if [[ "$served" == "$VERSION" ]]; then
    echo "    version на сервере: $served — совпадает со сборкой"
else
    echo "    version на сервере: $served — НЕ совпадает со сборкой $VERSION" >&2
    fail=1
fi

bundle_served="$(curl -sS --max-time 15 "$BASE_URL/index.html" | grep -o 'bundles/[0-9a-f]\{20\}' | head -1 | cut -d/ -f2)"
if [[ "$bundle_served" == "$bundle" ]]; then
    echo "    index.html ссылается на свежий бандл: $bundle_served"
else
    echo "    index.html ссылается на $bundle_served, а собрано $bundle" >&2
    fail=1
fi

echo
if [[ "$fail" == "0" ]]; then
    echo "==> РЕЛИЗ $VERSION ВЫЛОЖЕН. Клиенты с 1.12.26 увидят тост «Обновление VaVsta»"
    echo "    и перезагрузятся (клиент сам перезагружает страницу, когда /version разошёлся)."
else
    echo "==> ЕСТЬ ПРОВАЛЫ ПРОВЕРОК, см. выше" >&2
    exit 1
fi
