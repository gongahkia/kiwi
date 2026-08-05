#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

const requiredEntries = ["database.sql", "uploads.tar", "manifest.txt"];
const archiveNamePattern = /^wat-backup-(\d{8}T\d{6}Z)\.tar\.gz$/;

export function parseManifest(text) {
  const manifest = {};
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    const separator = line.indexOf("=");
    if (separator === -1) {
      manifest[line] = "";
      continue;
    }
    manifest[line.slice(0, separator)] = line.slice(separator + 1);
  }
  return manifest;
}

function normalizedEntry(entry) {
  return entry.replace(/^\.\//, "");
}

function isUnsafeEntry(entry) {
  const normalized = normalizedEntry(entry);
  return (
    !normalized ||
    isAbsolute(normalized) ||
    normalized === ".." ||
    normalized.startsWith("../") ||
    normalized.includes("/../")
  );
}

export function validateBackupEntries(entries) {
  const normalizedEntries = new Set(entries.map(normalizedEntry));
  const errors = [];
  for (const entry of entries) {
    if (isUnsafeEntry(entry)) errors.push(`unsafe archive entry: ${entry}`);
  }
  for (const entry of requiredEntries) {
    if (!normalizedEntries.has(entry)) errors.push(`missing archive entry: ${entry}`);
  }
  return errors;
}

function tar(args, options = {}) {
  return execFileSync("tar", args, { encoding: "utf8", ...options });
}

function readArchiveEntries(archivePath) {
  return tar(["-tzf", archivePath]).split(/\r?\n/).filter(Boolean);
}

export function validateBackupArchive(archivePath) {
  const errors = [];
  if (!archivePath) {
    return { errors: ["backup archive path is required"], ok: false };
  }

  const archiveName = basename(archivePath);
  const archiveNameMatch = archiveName.match(archiveNamePattern);
  if (!archiveNameMatch) errors.push(`invalid backup archive name: ${archiveName}`);

  let entries = [];
  try {
    entries = readArchiveEntries(archivePath);
    errors.push(...validateBackupEntries(entries));
  } catch (error) {
    return {
      archivePath,
      errors: [`cannot read backup archive: ${error.message}`],
      ok: false
    };
  }

  const workDir = mkdtempSync(join(tmpdir(), "wat-backup-verify-"));
  try {
    tar(["-xzf", archivePath, "-C", workDir, ...requiredEntries]);

    const manifest = parseManifest(readFileSync(join(workDir, "manifest.txt"), "utf8"));
    if (manifest.created_at !== archiveNameMatch?.[1]) {
      errors.push("manifest created_at does not match archive filename timestamp");
    }
    if (manifest.database_dump !== "database.sql") {
      errors.push("manifest database_dump must be database.sql");
    }
    if (manifest.uploads_archive !== "uploads.tar") {
      errors.push("manifest uploads_archive must be uploads.tar");
    }

    if (statSync(join(workDir, "database.sql")).size === 0) {
      errors.push("database.sql is empty");
    }
    try {
      tar(["-tf", join(workDir, "uploads.tar")]);
    } catch (error) {
      errors.push(`uploads.tar is not readable: ${error.message}`);
    }

    return { archivePath, entries, errors, manifest, ok: errors.length === 0 };
  } catch (error) {
    return {
      archivePath,
      entries,
      errors: [...errors, `cannot validate backup payload: ${error.message}`],
      ok: false
    };
  } finally {
    rmSync(workDir, { force: true, recursive: true });
  }
}

function main() {
  const archivePath = process.argv[2] ?? process.env.BACKUP_ARCHIVE;
  const result = validateBackupArchive(archivePath);
  if (!result.ok) {
    for (const error of result.errors) console.error(error);
    process.exit(1);
  }
  console.log(`backup archive ok: ${archivePath}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
