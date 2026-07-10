import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import { validateBackupArchive, validateBackupEntries } from "./verify-backup-archive.mjs";

function withTempDir(run) {
  const dir = mkdtempSync(join(tmpdir(), "wat-backup-test-"));
  try {
    return run(dir);
  } finally {
    rmSync(dir, { force: true, recursive: true });
  }
}

function makeArchive(dir, { timestamp = "20260710T120000Z", manifestTimestamp = timestamp } = {}) {
  const sourceDir = join(dir, "source");
  const emptyUploadsDir = join(dir, "uploads");
  mkdirSync(sourceDir);
  mkdirSync(emptyUploadsDir);
  execFileSync("tar", ["-cf", join(sourceDir, "uploads.tar"), "-C", emptyUploadsDir, "."]);
  writeFileSync(join(sourceDir, "database.sql"), "select 1;\n");
  writeFileSync(
    join(sourceDir, "manifest.txt"),
    `created_at=${manifestTimestamp}\ndatabase_dump=database.sql\nuploads_archive=uploads.tar\n`
  );

  const archivePath = join(dir, `wat-backup-${timestamp}.tar.gz`);
  execFileSync("tar", [
    "-czf",
    archivePath,
    "-C",
    sourceDir,
    "database.sql",
    "uploads.tar",
    "manifest.txt"
  ]);
  return archivePath;
}

describe("backup archive verification", () => {
  it("accepts archives produced by backup.sh", () =>
    withTempDir((dir) => {
      const result = validateBackupArchive(makeArchive(dir));

      assert.equal(result.ok, true);
      assert.deepEqual(result.errors, []);
      assert.equal(result.manifest.created_at, "20260710T120000Z");
    }));

  it("rejects timestamp drift between archive name and manifest", () =>
    withTempDir((dir) => {
      const result = validateBackupArchive(
        makeArchive(dir, { manifestTimestamp: "20260710T120001Z" })
      );

      assert.equal(result.ok, false);
      assert.match(result.errors.join("\n"), /created_at/);
    }));

  it("rejects missing or unsafe archive entries", () => {
    assert.deepEqual(validateBackupEntries(["database.sql", "uploads.tar"]), [
      "missing archive entry: manifest.txt"
    ]);
    assert.deepEqual(validateBackupEntries(["database.sql", "uploads.tar", "../secret"]), [
      "unsafe archive entry: ../secret",
      "missing archive entry: manifest.txt"
    ]);
  });
});
