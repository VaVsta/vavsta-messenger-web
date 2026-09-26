#!/usr/bin/env bash
# Наложение брендинга VaVsta на УЖЕ СОБРАННУЮ статику Element Web.
#
# Зачем: на сервере chat.vavsta.ru лежит сборка element-web, а брендинг раньше
# наклеивался руками на index.html/icon и при каждой пересборки откатывался.
# Ребрендинг теперь ALSO сидит в исходниках форка (apps/web/src/vector/index.html,
# res/manifest.json, res/vector-icons, SdkConfig.ts) — но полная пересборка element-web
# тянет pnpm install на несколько гигабайт и апгрейдит версию клиента.
# Этот скрипт — быстрый путь: патчит развёрнутую статику, не трогая бандлы.
#
# Использование: ./deploy/vavsta-branding.sh <ssh-хост> [webroot]
set -euo pipefail

HOST="${1:?usage: $0 <ssh-хост> [webroot]}"
WEBROOT="${2:-/var/www/element}"
ASSETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assets"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH=(ssh -o IdentitiesOnly=yes -o BatchMode=yes)

echo "==> Бэкап текущего состояния на $HOST"
"${SSH[@]}" "root@$HOST" "set -e
    BK=/var/backups/element-branding/\$(date +%Y%m%d-%H%M%S)
    mkdir -p \$BK
    cd '$WEBROOT'
    cp -a index.html manifest.json vector-icons themes/element/img/logos themes/element/img/backgrounds static \$BK/ 2>/dev/null || true
    for b in bundles/*/init.js bundles/*/error-view.js; do
        [ -f \"\$b\" ] && cp -a --parents \$b \$BK/ || true
    done
    echo \"    бэкап: \$BK\"
    echo \$BK > /var/backups/element-branding/.last
"

echo "==> Копируем иконки/логотип/og на $HOST"
tar -C "$ASSETS_DIR" -czf - . | "${SSH[@]}" "root@$HOST" "set -e
    rm -rf /tmp/vavsta-branding && mkdir -p /tmp/vavsta-branding
    cd /tmp/vavsta-branding && tar xzf -
    cd '$WEBROOT'
    cp -f /tmp/vavsta-branding/icons/*.png vector-icons/
    cp -f /tmp/vavsta-branding/opengraph.png themes/element/img/logos/opengraph.png
    cp -f /tmp/vavsta-branding/vavsta-logo.png themes/element/img/logos/vavsta-logo.png
    cp -f /tmp/vavsta-branding/vavsta-splash.jpg themes/element/img/backgrounds/vavsta-splash.jpg
    cp -f /tmp/vavsta-branding/vavsta-manifest.json manifest.json
    cp -f /tmp/vavsta-branding/static/*.html static/
    chown -R www-data:www-data vector-icons themes/element/img/logos themes/element/img/backgrounds static manifest.json
"

echo "==> Патчим index.html (title/og/иконки/noscript)"
"${SSH[@]}" "root@$HOST" "python3 - <<'PY'
import re
p = '$WEBROOT/index.html'
s = open(p, encoding='utf-8').read()
orig = s

# иконки -> свежие хэши из assets/icons (ищем сами, чтобы не хардкодить)
import glob, os, re as _re
ic = {}
for f in glob.glob('$WEBROOT/vector-icons/*.png'):
    b = os.path.basename(f)
    m = _re.match(r'^(\d+)\.([0-9a-f]{7})\.png$', b)
    if m:
        ic[m.group(1)] = 'vector-icons/' + b
for size in ('24', '120', '144', '152', '180', '512'):
    if size in ic:
        s = _re.sub(r'(href=\")[^\"]*vector-icons/%s(\.[0-9a-f]{7})?\.png(\")' % size,
                    lambda mo: mo.group(1) + ic[size] + mo.group(3), s)
s = _re.sub(r'(href=\")[^\"]*vavsta-icon\.png(\")', lambda mo: mo.group(1) + ic.get('512', 'vavsta-icon.png') + mo.group(2), s)

# og:image -> свой домен
s = s.replace('https://app.element.io/themes/element/img/logos/opengraph.png',
              'https://chat.vavsta.ru/themes/element/img/logos/opengraph.png')
if 'og:site_name' not in s:
    s = s.replace('<meta property=\"og:image\"',
                  '<meta property=\"og:title\" content=\"VaVsta\" />\n'
                  '    <meta property=\"og:site_name\" content=\"VaVsta\" />\n'
                  '    <meta property=\"og:image\"', 1)
s = re.sub(r'<noscript>.*?</noscript>',
            '<noscript>Sorry, VaVsta requires JavaScript to be enabled.</noscript>', s, flags=re.S)
s = s.replace('<meta name=\"theme-color\" content=\"#ffffff\">',
              '<meta name=\"theme-color\" content=\"#160A30\">')
if s == orig:
    # уже пропатчен — идемпотентный повторный прогон, это норма
    assert '<title>VaVsta</title>' in s, 'index.html не похож на element-web: нет ни Element, ни VaVsta'
    print('    index.html: уже пропатан, пропускаем')
else:
    open(p, 'w', encoding='utf-8').write(s)
    print('    index.html: ok')
PY"

echo "==> Патчим бандлы (логотип входа + отключаем рекламу Element Desktop)"
"${SSH[@]}" "root@$HOST" "set -e
    cd '$WEBROOT'
    for f in bundles/*/init.js bundles/*/error-view.js; do
        [ -f \"\$f\" ] || continue
        [ -f \"\$f.bak-branding\" ] || cp \$f \$f.bak-branding
        sed -i -E \
            -e 's#auth_header_logo_url:\"[^\"]*element-logo\.svg\"#auth_header_logo_url:\"themes/element/img/logos/vavsta-logo.png\"#g' \
            -e 's#\"themes/element/img/logos/element-logo\.svg\"#\"themes/element/img/logos/vavsta-logo.png\"#g' \
            -e 's#themes/element/img/logos/element-app-logo\.png#themes/element/img/logos/vavsta-logo.png#g' \
            -e 's#logo_link_url:\"https://element\.io\"#logo_link_url:\"https://chat.vavsta.ru/\"#g' \
            -e 's#themes/element/img/backgrounds/lake\.jpg#themes/element/img/backgrounds/vavsta-splash.jpg#g' \
            \"\$f\"
    done
    chown -R www-data:www-data bundles
    echo \"    бандлы: ok\"
"

echo "==> Проверка"
"${SSH[@]}" "root@$HOST" "cd '$WEBROOT'
    echo '    title:   ' \$(grep -o '<title>[^<]*' index.html)
    echo '    og:      ' \$(grep -o 'og:image\" content=\"[^\"]*' index.html)
    echo '    manifest:' \$(python3 -c \"import json;d=json.load(open('manifest.json'));print(d['name'], d['theme_color'])\")
    echo '    logo:    ' \$(grep -c vavsta-logo bundles/*/init.js)
"

echo "==> Готово. Проверь в браузере https://$HOST/ (Ctrl+Shift+R — сбросить кеш)"
