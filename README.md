# VaVsta Messenger Web

> **Неофициальный форк.** Этот проект — переименованный и переоформленный
> форк [Element Web](https://github.com/element-hq/element-web)
> (© New Vector Ltd / Element). Он **не связан с Element, не одобрен и не
> поддерживается им**, а также не использует имя или логотип «Element».
> «VaVsta», VaVsta Messenger и VaVsta Call — собственные торговые марки
> автора.

Веб-клиент для Matrix-хоумсервера `chat.vavsta.ru`, построенный на базе
Element Web — Matrix веб- и десктоп-клиента на
[Matrix JS SDK](https://github.com/matrix-org/matrix-js-sdk). Это веб-версия
Android-клиента [VaVsta Messenger](https://github.com/VaVsta/vavsta-messenger).

## Что изменено относительно апстрима

- **Идентичность:** переименование в «VaVsta», собственный бренд, фавиконка,
  сплеш на странице входа вместо фото Element.
- **Тема VaVsta** для светлой и тёмной тем: фиолетовый акцент вместо
  зелёного, скругления в стиле Material 3, прошитые через обе темы.
- **Страница входа:** сплеш вместо стандартного скриншота Element, скруглённая
  CTA, формулировки «чат» вместо «комната» в UI-строках.
- **Мобильный лендинг:** кнопка «Скачать APK» со ссылкой на OTA-манифест
  Android-клиента, плюс нормальная `/favicon.ico` для вида «добавить на
  главный экран».
- **Релизные заметки:** показ в тосте внутри приложения после обновления
  вместо апстримного ChangelogDialog.
- Всё остальное повторяет апстрим-ветку `develop`, пока что-то не трогается
  намеренно.

## Сборка и выкладка

Репо — апстримовский монорепо (приложения — в `apps/`); сборка через nx как
обычно (`yarn install`, затем `yarn nx build web` для веб-бандла; подробности —
в апстримных `docs/monorepo.md` и `apps/web/README.md`). Версия берётся из
`apps/web/package.json` плагином `VersionFilePlugin` и запекается в бандл и
в эндпоинт `/version`, так что они не могут разойтись.

Выкладка на `chat.vavsta.ru` автоматизирована в
[`deploy/release-web.sh`](deploy/release-web.sh):
`./deploy/release-web.sh --deploy --bump patch` собирает и заливает бандл.
Скрипт никогда не трогает: серверный `config.json` /
`config.chat.vavsta.ru.json`, папку OTA Android `vavsta-messenger/` и
`.well-known/`.

## Поддерживаемые браузеры

Та же матрица, что и у апстримного Element Web: две последние мажорные версии
Chrome, Firefox и Edge на десктопе, плюс мобильный веб в актуальных на текущий
день браузерах Android/iOS. Подробности — в апстрим-README.

## Лицензия

Данное ПО — форк Element Web, используемый под
**GNU Affero General Public License, версия 3 (AGPL-3.0)**.

Авторское право апстрима:
- Copyright (c) 2014–2017 OpenMarket Ltd
- Copyright (c) 2017 Vector Creations Ltd
- Copyright (c) 2017–2025 New Vector Ltd

Изменения форка принадлежат автору VaVsta (см. `git log`).

«Element» — товарный знак Element (New Vector Ltd / Element Creations Ltd).
Это независимый форк, и ничего в нём не даёт права на использование бренда
Element.