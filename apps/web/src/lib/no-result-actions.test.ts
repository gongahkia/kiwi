import { describe, expect, it } from "vitest";

import { noResultActions } from "./no-result-actions";

describe("noResultActions", () => {
  it("routes no-result searches to reviewable suggestions and personal entries", () => {
    expect(noResultActions("unknown term")).toEqual([
      {
        href: "/suggest?term=unknown%20term",
        label: "Suggest for review"
      },
      {
        href: "/personal?term=unknown%20term",
        label: "Save personal entry"
      }
    ]);
  });
});
