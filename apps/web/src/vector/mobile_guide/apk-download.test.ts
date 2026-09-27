/*
Copyright 2026 Element Creations Ltd.

SPDX-License-Identifier: AGPL-3.0-only OR GPL-3.0-only OR LicenseRef-Element-Commercial
Please see LICENSE files in the repository root for full details.
*/

// @vitest-environment happy-dom

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fetchMock from "@fetch-mock/vitest";

import { resolveApkUrl, setupApkDownload } from "./apk-download";

const ORIGIN = window.location.origin;
const OTHER_SCHEME = ORIGIN.startsWith("https") ? ORIGIN.replace(/^https/, "http") : ORIGIN.replace(/^http/, "https");
const MANIFEST_URL = new URL("../vavsta-messenger/version.json", window.location.href).toString();
const APK_PATH = "/vavsta-messenger/vavsta-messenger-arm64-202608042.apk";

/** Мини-разметка страницы: ровно те id, которые читает apk-download.ts. */
function renderPage(): HTMLAnchorElement {
    document.body.innerHTML = `
        <a id="apk_download" href="#" download hidden></a>
        <p id="apk_meta"></p>
        <p id="apk_notes"></p>
        <p id="apk_error" hidden></p>
        <div id="apk_details" hidden><code id="apk_sha"></code></div>
    `;
    return document.getElementById("apk_download") as HTMLAnchorElement;
}

describe("resolveApkUrl", () => {
    it("принимает apk на нашем домене из каталога vavsta-messenger", () => {
        const url = resolveApkUrl(`${ORIGIN}${APK_PATH}`, ORIGIN);
        expect(url?.pathname).toBe(APK_PATH);
    });

    it.each([
        ["чужой домен", "https://example.com/vavsta-messenger/x.apk"],
        ["другая схема", `${OTHER_SCHEME}${APK_PATH}`],
        ["путь вне каталога", `${ORIGIN}/bundles/x.apk`],
        ["не apk", `${ORIGIN}/vavsta-messenger/version.json`],
        ["обход каталога", `${ORIGIN}/vavsta-messenger/../evil.apk`],
        ["протокол-относительная ссылка", "//example.com/vavsta-messenger/x.apk"],
        ["не строка", 42],
        ["пустая строка", ""],
        ["отсутствует", undefined],
    ] as [string, unknown][])("отклоняет %s", (_case, raw) => {
        expect(resolveApkUrl(raw, ORIGIN)).toBeNull();
    });
});

describe("setupApkDownload", () => {
    beforeEach(() => {
        fetchMock.mockReset();
    });

    afterEach(() => {
        fetchMock.mockRestore();
    });

    it("подставляет ссылку, имя файла и метаданные из манифеста", async () => {
        const button = renderPage();
        fetchMock.get(MANIFEST_URL, {
            versionCode: 202608042,
            versionName: "1.0",
            apkUrl: `${ORIGIN}${APK_PATH}`,
            sha256: "dc0d9b943413cb1aec88dab3feef5c5c7b8cf9c94ed1d7227a1314f6e61db770",
            sizeBytes: 117598464,
            notes: "Первая рабочая OTA",
        });

        await setupApkDownload();

        expect(button.hidden).toBe(false);
        expect(button.getAttribute("href")).toBe(APK_PATH);
        expect(button.getAttribute("download")).toBe("vavsta-messenger-arm64-202608042.apk");
        expect(document.getElementById("apk_meta")?.textContent).toBe("версия 1.0 · сборка 202608042 · 112,2 МБ");
        expect(document.getElementById("apk_notes")?.textContent).toBe("Первая рабочая OTA");
        expect(document.getElementById("apk_sha")?.textContent).toBe(
            "dc0d9b943413cb1aec88dab3feef5c5c7b8cf9c94ed1d7227a1314f6e61db770",
        );
        expect(document.getElementById("apk_details")?.hidden).toBe(false);
        expect(document.getElementById("apk_error")?.hidden).toBe(true);
    });

    it("оставляет кнопку скрытой, если манифест недоступен", async () => {
        const button = renderPage();
        fetchMock.get(MANIFEST_URL, 500);

        await setupApkDownload();

        expect(button.hidden).toBe(true);
        expect(document.getElementById("apk_error")?.hidden).toBe(false);
    });

    it("оставляет кнопку скрытой, если apkUrl с чужого домена", async () => {
        const button = renderPage();
        fetchMock.get(MANIFEST_URL, {
            versionCode: 1,
            versionName: "1.0",
            apkUrl: "https://example.com/evil.apk",
        });

        await setupApkDownload();

        expect(button.hidden).toBe(true);
        expect(document.getElementById("apk_error")?.hidden).toBe(false);
    });

    it("не падает, если на странице нет кнопки", async () => {
        document.body.innerHTML = "";
        fetchMock.get(MANIFEST_URL, 200);

        await expect(setupApkDownload()).resolves.toBeUndefined();
    });
});
