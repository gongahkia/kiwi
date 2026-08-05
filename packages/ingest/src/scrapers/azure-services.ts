import { execFile as execFileCallback } from "node:child_process";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { promisify } from "node:util";

import type { RawEntry, ScraperPlugin } from "../scraper.js";

const execFile = promisify(execFileCallback);
const sourceName = "azure-services";
const repoUrl = "https://github.com/Azure/azure-rest-api-specs.git";
const blobBaseUrl = "https://github.com/Azure/azure-rest-api-specs/blob/main";

export const azureServicesScraper: ScraperPlugin = {
  name: sourceName,
  license: "MIT",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const dir = await mkdtemp(join(tmpdir(), "wat-azure-specs-"));

    try {
      await execFile("git", [
        "clone",
        "--depth",
        "1",
        "--filter=blob:none",
        "--sparse",
        repoUrl,
        dir
      ]);
      await execFile("git", [
        "-C",
        dir,
        "sparse-checkout",
        "set",
        "--no-cone",
        "specification/**/readme.md"
      ]);

      for (const file of await readmeFiles(join(dir, "specification"))) {
        const relativePath = relative(dir, file);
        const entry = readmeToRawEntry(
          serviceNameFromPath(relativePath),
          relativePath,
          await readFile(file, "utf8"),
          retrievedAt
        );
        if (entry) yield entry;
      }
    } finally {
      await rm(dir, { force: true, recursive: true });
    }
  }
};

export function readmeToRawEntry(
  service: string,
  path: string,
  readme: string,
  retrievedAt: string
): RawEntry | null {
  const title = cleanText(readme.match(/^#\s+(.+)$/m)?.[1] ?? "");
  if (!service || !title) return null;

  return {
    domains: ["azure", "cloud", "service names"],
    expansion: title,
    meaning: title,
    sources: [
      {
        license: "MIT",
        publisher: "Azure REST API Specs",
        retrieved_at: retrievedAt,
        snippet: `${service}: ${title}`,
        source_quality: "canonical",
        title: `Azure REST API spec: ${service}`,
        url: `${blobBaseUrl}/${path}`
      }
    ],
    term: service
  };
}

async function readmeFiles(root: string): Promise<string[]> {
  const files: string[] = [];
  for (const item of await readdir(root, { withFileTypes: true })) {
    const path = join(root, item.name);
    if (item.isDirectory()) {
      files.push(...(await readmeFiles(path)));
    } else if (item.isFile() && item.name.toLowerCase() === "readme.md") {
      files.push(path);
    }
  }
  return files.sort((left, right) => left.localeCompare(right));
}

function serviceNameFromPath(path: string): string {
  const parts = path.split("/");
  const service = parts[1] ?? "";
  const parent = parts[parts.length - 2] ?? "";
  return parent && parent !== "resource-manager" && parent !== "data-plane"
    ? `${service}/${parent}`
    : service;
}

function cleanText(input: string): string {
  return input.replace(/\s+/g, " ").trim();
}
