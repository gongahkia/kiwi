import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { requiredFlyTokens, validateFlyConfig } from "./validate-fly-config.mjs";

function readFlyFiles() {
  return Object.fromEntries(
    Object.keys(requiredFlyTokens).map((path) => [path, readFileSync(path, "utf8")])
  );
}

describe("Fly config", () => {
  it("covers web plus optional Slack runtime resources", () => {
    const result = validateFlyConfig(readFlyFiles());

    assert.equal(result.ok, true);
    assert.deepEqual(result.missing, []);
  });

  it("fails closed when Slack runtime coverage drifts", () => {
    const result = validateFlyConfig({ "infra/fly/main.tf": 'resource "fly_app" "web" {}' });

    assert.equal(result.ok, false);
    assert.match(result.missing.join("\n"), /resource "fly_machine" "slack"/);
    assert.match(result.missing.join("\n"), /infra\/fly\/variables\.tf/);
  });
});
