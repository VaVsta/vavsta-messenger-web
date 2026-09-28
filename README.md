# VaVsta Messenger Web

> **Unofficial fork.** This project is a renamed and re-branded fork of
> [Element Web](https://github.com/element-hq/element-web)
> (c) New Vector Ltd / Element. It is **not affiliated with, endorsed or
> sponsored by Element**, and does not use the "Element" name or logo.
> "VaVsta", VaVsta Messenger and VaVsta Call are the author's own marks.

Web client for the Matrix homeserver `chat.vavsta.ru`, built on top of
Element Web — the Matrix web & desktop client powered by the
[Matrix JS SDK](https://github.com/matrix-org/matrix-js-sdk). This is the
companion web app to the [VaVsta Messenger](https://github.com/vavsta/vavsta-messenger)
Android client.

## What changed vs upstream

- **Identity:** rename to "VaVsta", own brand, favicon, splash on the login
  page instead of the Element photo.
- **VaVsta theme** for both light and dark: purple accent instead of green,
  rounded, Material 3-style corners wired through both themes.
- **Login page:** splash instead of the stock Element screenshot, rounded CTA,
  "чат" ("chat") wording instead of "room" in the UI strings.
- **Mobile landing:** a "Download APK" button linking to the Android OTA
  manifest, plus a proper `/favicon.ico` for the app-install view.
- **Release notes:** shown in an in-app toast after an update instead of the
  upstream ChangelogDialog.
- Everything else tracks upstream `develop` unless deliberately touched.

## Building & releasing

The repo is the upstream Element monorepo (apps live under `apps/`); build
with nx as usual (`yarn install`, then
`yarn nx build web` for the web bundle — see `docs/monorepo.md` and
`apps/web/README.md` upstream). Version is taken from `apps/web/package.json`
by `VersionFilePlugin` and baked into the bundle and the `/version` endpoint,
so the two can never disagree.

Deployment to `chat.vavsta.ru` is automated in
[`deploy/release-web.sh`](deploy/release-web.sh):
`./deploy/release-web.sh --deploy --bump patch` builds and uploads the bundle.
What the script never touches: the server-side `config.json` /
`config.chat.vavsta.ru.json`, the Android OTA folder `vavsta-messenger/`, and
`.well-known/`.

## Supported browsers

Same matrix as upstream Element Web: the last 2 major versions of Chrome,
Firefox and Edge on desktop, plus mobile web on current stable Android/iOS
browsers. See the upstream README for details.

## License

This software is a fork of Element Web and is used under the
**GNU Affero General Public License, version 3 (AGPL-3.0)**.

Upstream copyright:
- Copyright (c) 2014–2017 OpenMarket Ltd
- Copyright (c) 2017 Vector Creations Ltd
- Copyright (c) 2017–2025 New Vector Ltd

This fork adds changes by the VaVsta author (see `git log`).

"Element" is a trademark of Element (New Vector Ltd / Element Creations Ltd).
This project is an independent fork and nothing here grants a right to use the
Element brand.