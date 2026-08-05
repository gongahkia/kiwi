import { mkdir, readdir, readFile, stat, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

interface ContemporaryEntry {
  aliases?: string[];
  contemporaries?: string[];
  id?: string;
  term?: string;
  term_normalized?: string;
}

interface CorpusFile {
  entries?: ContemporaryEntry[];
}

interface EntryRef {
  entry: ContemporaryEntry;
  id: string;
  index: number;
  keys: Set<string>;
  term: string;
}

export interface ContemporaryLintIssue {
  code: "asymmetric_contemporary" | "contemporary_self_reference" | "unresolved_contemporary";
  contemporary: string;
  entry_id: string;
  target_entry_id?: string;
  target_term?: string;
  term: string;
}

export interface SymmetricReviewFile {
  generated_at: string;
  suggestions: SymmetricSuggestion[];
}

export interface SymmetricSuggestion {
  add_contemporaries: string[];
  entry_id: string;
  source_entries: Array<{ entry_id: string; term: string }>;
  term: string;
}

const rootDir = fileURLToPath(new URL("../../..", import.meta.url));
const manualSeedPath = fileURLToPath(new URL("../seeds/manual.json", import.meta.url));
const defaultReviewPath = join(rootDir, "reports", "contemporaries-symmetric-review.json");

export function lintContemporaries(entries: ContemporaryEntry[]): ContemporaryLintIssue[] {
  const refs = entries.map(toEntryRef);
  const resolver = buildResolver(refs);
  const issues: ContemporaryLintIssue[] = [];

  for (const ref of refs) {
    for (const contemporary of ref.entry.contemporaries ?? []) {
      const key = normalizeLookupKey(contemporary);
      if (!key) continue;
      if (ref.keys.has(key)) {
        issues.push({
          code: "contemporary_self_reference",
          contemporary,
          entry_id: ref.id,
          term: ref.term
        });
        continue;
      }

      const targets = resolver.get(key) ?? [];
      if (targets.length === 0) {
        issues.push({
          code: "unresolved_contemporary",
          contemporary,
          entry_id: ref.id,
          term: ref.term
        });
        continue;
      }

      const reciprocal = targets.some((target) =>
        contemporaryKeys(target.entry).some((targetKey) => ref.keys.has(targetKey))
      );
      if (!reciprocal) {
        const target = targets[0];
        issues.push({
          code: "asymmetric_contemporary",
          contemporary,
          entry_id: ref.id,
          target_entry_id: target?.id,
          target_term: target?.term,
          term: ref.term
        });
      }
    }
  }

  return issues;
}

export function buildSymmetricReview(issues: ContemporaryLintIssue[]): SymmetricReviewFile {
  const suggestions = new Map<string, SymmetricSuggestion>();

  for (const issue of issues) {
    if (issue.code !== "asymmetric_contemporary" || !issue.target_entry_id || !issue.target_term) {
      continue;
    }

    const suggestion =
      suggestions.get(issue.target_entry_id) ??
      ({
        add_contemporaries: [],
        entry_id: issue.target_entry_id,
        source_entries: [],
        term: issue.target_term
      } satisfies SymmetricSuggestion);
    if (!suggestion.add_contemporaries.includes(issue.term)) {
      suggestion.add_contemporaries.push(issue.term);
    }
    if (!suggestion.source_entries.some((entry) => entry.entry_id === issue.entry_id)) {
      suggestion.source_entries.push({ entry_id: issue.entry_id, term: issue.term });
    }
    suggestions.set(issue.target_entry_id, suggestion);
  }

  return {
    generated_at: new Date().toISOString(),
    suggestions: [...suggestions.values()].sort((left, right) =>
      left.term.localeCompare(right.term)
    )
  };
}

function toEntryRef(entry: ContemporaryEntry, index: number): EntryRef {
  const term = entry.term ?? entry.id ?? `entry-${index}`;
  return {
    entry,
    id: entry.id ?? term,
    index,
    keys: entryKeys(entry),
    term
  };
}

function buildResolver(refs: EntryRef[]): Map<string, EntryRef[]> {
  const resolver = new Map<string, EntryRef[]>();
  for (const ref of refs) {
    for (const key of ref.keys) {
      const current = resolver.get(key) ?? [];
      current.push(ref);
      resolver.set(key, current);
    }
  }
  return resolver;
}

function entryKeys(entry: ContemporaryEntry): Set<string> {
  const keys = new Set<string>();
  if (entry.term_normalized) keys.add(entry.term_normalized.toLowerCase());
  if (entry.term) keys.add(normalizeLookupKey(entry.term));
  for (const alias of entry.aliases ?? []) keys.add(normalizeLookupKey(alias));
  keys.delete("");
  return keys;
}

function contemporaryKeys(entry: ContemporaryEntry): string[] {
  return (entry.contemporaries ?? []).map(normalizeLookupKey).filter((key) => key.length > 0);
}

function normalizeLookupKey(input: string): string {
  return input
    .normalize("NFKD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}\s]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

async function readEntries(paths: string[]): Promise<ContemporaryEntry[]> {
  const entries: ContemporaryEntry[] = [];
  const seen = new Set<string>();
  for (const path of paths) {
    const resolved = resolveRepoPath(path);
    if (seen.has(resolved)) continue;
    seen.add(resolved);
    entries.push(...(await readEntriesFromPath(resolved)));
  }
  return entries;
}

async function readEntriesFromPath(path: string): Promise<ContemporaryEntry[]> {
  const info = await stat(path);
  if (info.isDirectory()) {
    const entries: ContemporaryEntry[] = [];
    for (const item of await readdir(path, { withFileTypes: true })) {
      entries.push(...(await readEntriesFromPath(join(path, item.name))));
    }
    return entries;
  }
  if (!info.isFile() || !path.endsWith(".json")) return [];

  const parsed = JSON.parse(await readFile(path, "utf8")) as CorpusFile;
  return parsed.entries ?? [];
}

function resolveRepoPath(path: string): string {
  return isAbsolute(path) ? path : join(rootDir, path);
}

interface CliOptions {
  fix: boolean;
  inputPaths: string[];
  reviewPath: string;
}

function parseArgs(args: string[]): CliOptions {
  const inputPaths: string[] = [];
  let fix = false;
  let reviewPath = defaultReviewPath;

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--fix") {
      fix = true;
    } else if (arg === "--review-path") {
      const next = args[index + 1];
      if (!next) throw new Error("missing --review-path value");
      reviewPath = resolveRepoPath(next);
      index += 1;
    } else if (arg) {
      inputPaths.push(arg);
    }
  }

  return { fix, inputPaths, reviewPath };
}

export async function writeSymmetricReview(
  path: string,
  review: SymmetricReviewFile
): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(review, null, 2)}\n`);
}

function formatIssue(issue: ContemporaryLintIssue): string {
  if (issue.code === "unresolved_contemporary") {
    return `${issue.entry_id}: unresolved contemporary ${issue.contemporary}`;
  }
  if (issue.code === "asymmetric_contemporary") {
    return `${issue.entry_id}: ${issue.contemporary} missing reciprocal contemporary ${issue.term}`;
  }
  return `${issue.entry_id}: self contemporary ${issue.contemporary}`;
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const entries = await readEntries([manualSeedPath, ...options.inputPaths]);
  const issues = lintContemporaries(entries);

  if (options.fix) {
    const review = buildSymmetricReview(issues);
    if (review.suggestions.length > 0) {
      await writeSymmetricReview(options.reviewPath, review);
      console.error(`wrote ${options.reviewPath}`);
    }
  }

  if (issues.length > 0) {
    for (const issue of issues) console.error(formatIssue(issue));
    process.exitCode = 1;
    return;
  }

  console.log(`contemporaries lint ok: ${entries.length} entries checked`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  void main();
}
