import { describe, expect, it } from "vitest";

import { paginateItems, paginationHeaders } from "./pagination";

describe("pagination", () => {
  it("returns a bounded page and next cursor", () => {
    expect(paginateItems([1, 2, 3], new URLSearchParams("limit=2"))).toEqual({
      items: [1, 2],
      page: {
        cursor: null,
        limit: 2,
        next_cursor: "2",
        total: 3
      }
    });
  });

  it("continues from a cursor", () => {
    expect(paginateItems([1, 2, 3], new URLSearchParams("limit=2&cursor=2"))).toEqual({
      items: [3],
      page: {
        cursor: "2",
        limit: 2,
        next_cursor: null,
        total: 3
      }
    });
  });

  it("caps excessive limits", () => {
    expect(paginateItems([1, 2, 3], new URLSearchParams("limit=1000")).page.limit).toBe(200);
  });

  it("exports pagination headers", () => {
    const headers = paginationHeaders({
      cursor: null,
      limit: 2,
      next_cursor: "2",
      total: 3
    });

    expect(headers.get("x-page-limit")).toBe("2");
    expect(headers.get("x-page-total")).toBe("3");
    expect(headers.get("x-next-cursor")).toBe("2");
  });
});
