import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

import { sessionUserFromToken, testSessionToken } from "./session";

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    return /\.(ts|tsx)$/.test(name) && !/\.test\./.test(name) ? [path] : [];
  });
}

describe("session role helpers", () => {
  it("parses test admin sessions", async () => {
    await expect(sessionUserFromToken(testSessionToken())).resolves.toMatchObject({
      id: "user_admin",
      role: "admin",
      teamId: "team_1"
    });
  });

  it("parses member sessions", async () => {
    await expect(
      sessionUserFromToken(testSessionToken({ role: "member", userId: "user_platform" }))
    ).resolves.toMatchObject({
      id: "user_platform",
      role: "member"
    });
  });

  it("keeps production source off legacy wat_session cookies", () => {
    const root = join(process.cwd(), "src");
    const offenders = sourceFiles(root)
      .filter((path) => readFileSync(path, "utf8").includes("wat_session"))
      .map((path) => relative(root, path));

    expect(offenders).toEqual([]);
  });
});
