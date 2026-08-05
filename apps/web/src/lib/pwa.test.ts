import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { webManifest } from "./pwa";

describe("PWA metadata", () => {
  it("defines an installable web manifest", () => {
    expect(webManifest).toMatchObject({
      display: "standalone",
      id: "/",
      name: "wat",
      scope: "/",
      short_name: "wat",
      start_url: "/"
    });
    expect(webManifest.icons?.some((icon) => icon.purpose?.includes("maskable"))).toBe(true);
  });

  it("ships a service worker with fetch handling", () => {
    const serviceWorker = readFileSync("public/sw.js", "utf8");

    expect(serviceWorker).toContain('addEventListener("install"');
    expect(serviceWorker).toContain('addEventListener("activate"');
    expect(serviceWorker).toContain('addEventListener("fetch"');
    expect(serviceWorker).toContain("caches.open");
  });
});
