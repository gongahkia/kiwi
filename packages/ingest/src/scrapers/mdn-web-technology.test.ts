import { describe, expect, it } from "vitest";

import { markdownToRawEntry, webIndexToRawEntries } from "./mdn-web-technology.js";

describe("mdn web technology scraper", () => {
  it("maps the Web technology reference index to raw entries", () => {
    const entries = webIndexToRawEntries(
      [
        "---",
        "title: Web technology for developers",
        "slug: Web",
        "---",
        "",
        "## Web technology references",
        "",
        "- [Web APIs](/en-US/docs/Web/API)",
        "  - : JavaScript programming APIs you can use to build apps on the Web.",
        "- [Progressive Web Apps (PWAs)](/en-US/docs/Web/Progressive_web_apps)",
        "  - : Progressive Web Apps provide a user experience similar to native mobile apps.",
        "",
        "## Developer tools documentation",
        "",
        "- [Chrome DevTools](https://developer.chrome.com/docs/devtools/)"
      ].join("\n"),
      "2026-06-24T00:00:00.000Z"
    );

    expect(entries).toHaveLength(2);
    expect(entries[0]).toMatchObject({
      aliases: [],
      domains: ["web platform", "mdn", "web technology", "web api"],
      expansion: "Web APIs",
      meaning: "JavaScript programming APIs you can use to build apps on the Web.",
      term: "Web APIs"
    });
    expect(entries[1]).toMatchObject({
      aliases: ["PWAs", "Progressive Web Apps (PWAs)"],
      domains: ["web platform", "mdn", "web technology", "pwa"],
      expansion: "Progressive Web Apps (PWAs)",
      term: "Progressive Web Apps"
    });
    expect(entries[1]?.sources[0]).toMatchObject({
      license: "CC-BY-SA-2.5",
      publisher: "Mozilla Contributors",
      source_quality: "canonical",
      url: "https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps"
    });
  });

  it("maps REST from the MDN supplemental concept page", () => {
    const entry = markdownToRawEntry(
      "files/en-us/glossary/rest/index.md",
      [
        "---",
        "title: REST",
        "slug: Glossary/REST",
        "---",
        "",
        "**REST** (Representational State Transfer) is a software architectural style for distributed hypermedia systems.",
        "",
        "## See also"
      ].join("\n"),
      "2026-06-24T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      aliases: ["Representational State Transfer"],
      domains: ["web platform", "mdn", "web technology", "http"],
      expansion: "Representational State Transfer",
      meaning:
        "REST (Representational State Transfer) is a software architectural style for distributed hypermedia systems.",
      term: "REST"
    });
    expect(entry?.sources[0]?.url).toBe("https://developer.mozilla.org/en-US/docs/Glossary/REST");
  });

  it("maps WebSocket and Service Worker API overview pages to concept entries", () => {
    const websocket = markdownToRawEntry(
      "files/en-us/web/api/websockets_api/index.md",
      [
        "---",
        "title: WebSocket API (WebSockets)",
        "slug: Web/API/WebSockets_API",
        "---",
        "",
        '{{DefaultAPISidebar("WebSockets API")}}{{AvailableInWorkers}}',
        "",
        "The **WebSocket API** makes it possible to open a two-way interactive communication session between the user's browser and a server."
      ].join("\n"),
      "2026-06-24T00:00:00.000Z"
    );
    const serviceWorker = markdownToRawEntry(
      "files/en-us/web/api/service_worker_api/index.md",
      [
        "---",
        "title: Service Worker API",
        "slug: Web/API/Service_Worker_API",
        "---",
        "",
        '{{DefaultAPISidebar("Service Workers API")}}{{AvailableInWorkers}}',
        "",
        "Service workers essentially act as proxy servers that sit between web applications, the browser, and the network."
      ].join("\n"),
      "2026-06-24T00:00:00.000Z"
    );

    expect(websocket).toMatchObject({
      aliases: ["WebSocket API (WebSockets)", "WebSockets"],
      domains: ["web platform", "mdn", "web technology", "web api"],
      expansion: "WebSocket API",
      term: "WebSocket"
    });
    expect(serviceWorker).toMatchObject({
      aliases: ["Service Worker API", "Service workers"],
      domains: ["web platform", "mdn", "web technology", "web api"],
      expansion: "Service Worker API",
      term: "Service Worker"
    });
  });
});
