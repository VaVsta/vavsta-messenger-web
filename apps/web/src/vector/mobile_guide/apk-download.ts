/*
Copyright 2026 Element Creations Ltd.

SPDX-License-Identifier: AGPL-3.0-only OR GPL-3.0-only OR LicenseRef-Element-Commercial
Please see LICENSE files in the repository root for full details.
*/

/*
 * Кнопка «Скачать APK» на странице мобильного приложения (/mobile_guide/).
 *
 * Ссылка намеренно не зашита в страницу: она всегда берётся из манифеста
 * /vavsta-messenger/version.json, который перезаписывает
 * element-x-android/tools/publish-ota.sh при публикации очередной сборки.
 * Зашитая константа навсегда осталась бы на самой первой версии.
 *
 * Манифест лежит на том же домене, что и сама страница, поэтому в href
 * попадает только путь: кнопка не превращается в ссылку наружу и работает
 * без внешнего CDN.
 */

import { logger } from "matrix-js-sdk/src/logger";

/** Каталог, в котором publish-ota.sh держит APK и манифест. */
const APK_DIR = "/vavsta-messenger/";

/** Обязательны versionCode, versionName и apkUrl, остальное может отсутствовать. */
interface ApkManifest {
    versionCode?: number;
    versionName?: string;
    apkUrl?: string;
    sha256?: string;
    sizeBytes?: number;
    notes?: string;
}

function formatSize(bytes: number): string {
    return `${(bytes / 1024 / 1024).toFixed(1).replace(".", ",")} МБ`;
}

/**
 * Проверяет apkUrl из манифеста: только наш домен и только файл внутри
 * каталога с APK. Манифест перезаписывается на сервере, и не должен уметь
 * сделать из этой страницы ссылку на что угодно. Сравнение origin заодно
 * закрывает схему (https на https-странице), поэтому отдельной проверки
 * протокола нет — иначе локальная разработка по http не работала бы.
 */
export function resolveApkUrl(raw: unknown, origin: string): URL | null {
    if (typeof raw !== "string" || raw === "") return null;

    let url: URL;
    try {
        url = new URL(raw);
    } catch {
        return null;
    }

    if (url.origin !== origin) return null;
    if (!url.pathname.startsWith(APK_DIR) || !url.pathname.endsWith(".apk")) return null;
    return url;
}

function setText(id: string, text: string | undefined): void {
    if (!text) return;
    const el = document.getElementById(id);
    if (el) el.textContent = text;
}

function show(id: string): void {
    const el = document.getElementById(id);
    if (el) el.hidden = false;
}

function fileNameOf(url: URL): string {
    const raw = url.pathname.slice(url.pathname.lastIndexOf("/") + 1);
    try {
        return decodeURIComponent(raw);
    } catch {
        return raw;
    }
}

/** Показывает кнопку загрузки, если манифест доступен и выглядит правдоподобно. */
export async function setupApkDownload(): Promise<void> {
    const button = document.getElementById("apk_download") as HTMLAnchorElement | null;
    if (!button) return;

    let manifest: ApkManifest;
    try {
        const response = await fetch(new URL("../vavsta-messenger/version.json", window.location.href), {
            cache: "no-cache",
        });
        if (!response.ok) throw new Error(`version.json: HTTP ${response.status}`);
        manifest = (await response.json()) as ApkManifest;
    } catch (e) {
        logger.warn("Не удалось получить манифест APK", e);
        show("apk_error");
        return;
    }

    const url = resolveApkUrl(manifest.apkUrl, window.location.origin);
    if (!url) {
        logger.error("Непроверяемый apkUrl в манифесте APK", manifest.apkUrl);
        show("apk_error");
        return;
    }

    button.href = url.pathname + url.search;
    button.download = fileNameOf(url);
    button.hidden = false;

    const parts: string[] = [];
    if (manifest.versionName) parts.push(`версия ${manifest.versionName}`);
    if (typeof manifest.versionCode === "number") parts.push(`сборка ${manifest.versionCode}`);
    if (typeof manifest.sizeBytes === "number") parts.push(formatSize(manifest.sizeBytes));
    setText("apk_meta", parts.join(" · "));
    setText("apk_notes", manifest.notes);
    setText("apk_sha", manifest.sha256);
    show("apk_details");
}
