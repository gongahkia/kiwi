#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const defaultQuery = "API";
const defaultTimeoutMs = 10000;

export function parseArgs(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const value = argv[index + 1];
    if (arg === "--") {
      continue;
    } else if (arg === "--url") {
      options.url = requiredValue(arg, value);
      index += 1;
    } else if (arg === "--terraform-dir") {
      options.terraformDir = requiredValue(arg, value);
      index += 1;
    } else if (arg === "--query") {
      options.query = requiredValue(arg, value);
      index += 1;
    } else if (arg === "--timeout-ms") {
      options.timeoutMs = Number(requiredValue(arg, value));
      index += 1;
    } else if (arg === "--api-key") {
      options.apiKey = requiredValue(arg, value);
      index += 1;
    } else if (arg === "--team-id") {
      options.teamId = requiredValue(arg, value);
      index += 1;
    } else if (arg === "--user-id") {
      options.userId = requiredValue(arg, value);
      index += 1;
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }
  return options;
}

function requiredValue(name, value) {
  if (!value || value.startsWith("--")) throw new Error(`${name} requires a value`);
  return value;
}

function envValue(env, name) {
  return env[name]?.trim() || null;
}

function normalizeBaseUrl(value) {
  const url = new URL(value);
  url.pathname = url.pathname.replace(/\/+$/, "");
  url.search = "";
  url.hash = "";
  return url.toString().replace(/\/+$/, "");
}

export function terraformWebUrl(terraformDir, execFile = execFileSync) {
  return String(
    execFile("terraform", [`-chdir=${terraformDir}`, "output", "-raw", "web_url"], {
      encoding: "utf8"
    })
  ).trim();
}

export function smokeConfig(argv, env = process.env, execFile = execFileSync) {
  const args = parseArgs(argv);
  if (args.help) return { help: true };
  const terraformDir = args.terraformDir ?? envValue(env, "WAT_TERRAFORM_DIR");
  const url =
    args.url ??
    envValue(env, "WAT_DEPLOY_URL") ??
    envValue(env, "WAT_API_BASE_URL") ??
    (terraformDir ? terraformWebUrl(terraformDir, execFile) : null);
  if (!url) {
    throw new Error("set --url, WAT_DEPLOY_URL, WAT_API_BASE_URL, or --terraform-dir");
  }
  const timeoutMs = args.timeoutMs ?? Number(envValue(env, "SMOKE_TIMEOUT_MS") ?? defaultTimeoutMs);
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) throw new Error("timeout must be positive");
  return {
    apiKey: args.apiKey ?? envValue(env, "WAT_API_KEY"),
    baseUrl: normalizeBaseUrl(url),
    query: args.query ?? envValue(env, "SMOKE_QUERY") ?? defaultQuery,
    teamId: args.teamId ?? envValue(env, "WAT_TEAM_ID"),
    timeoutMs,
    userId: args.userId ?? envValue(env, "WAT_USER_ID") ?? "deployment:smoke"
  };
}

function headers(config) {
  const result = { accept: "application/json" };
  if (config.apiKey) result.authorization = `Bearer ${config.apiKey}`;
  if (config.teamId) result["x-wat-team-id"] = config.teamId;
  if (config.userId) result["x-wat-user-id"] = config.userId;
  return result;
}

async function requestJson(label, url, config, fetchImpl) {
  const response = await fetchImpl(url, {
    headers: headers(config),
    signal: AbortSignal.timeout(config.timeoutMs)
  });
  const text = await response.text();
  let body = null;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      throw new Error(`${label} returned non-json body: ${text.slice(0, 200)}`);
    }
  }
  if (!response.ok) {
    throw new Error(`${label} returned ${response.status}: ${text.slice(0, 500)}`);
  }
  return body;
}

export async function smokeDeployment(config, fetchImpl = fetch) {
  const readyz = await requestJson("readyz", `${config.baseUrl}/readyz`, config, fetchImpl);
  if (readyz?.status !== "ok") {
    throw new Error(`readyz status was ${JSON.stringify(readyz?.status ?? readyz)}`);
  }
  const searchUrl = new URL("/api/v1/search", config.baseUrl);
  searchUrl.searchParams.set("q", config.query);
  searchUrl.searchParams.set("limit", "1");
  const search = await requestJson("search", searchUrl, config, fetchImpl);
  if (!Array.isArray(search?.matches)) throw new Error("search response missing matches array");
  if (search.matches.length < 1) throw new Error(`search returned no matches for ${config.query}`);
  return {
    matchCount: search.matches.length,
    query: config.query,
    readyz,
    search,
    url: config.baseUrl
  };
}

export function usage() {
  return [
    "Usage: pnpm smoke:deployment -- --url https://wat.example.com",
    "",
    "Inputs: --url, WAT_DEPLOY_URL, WAT_API_BASE_URL, or --terraform-dir infra/fly.",
    "Optional: --api-key, --team-id, --user-id, --query, --timeout-ms."
  ].join("\n");
}

async function main() {
  try {
    const config = smokeConfig(process.argv.slice(2));
    if (config.help) {
      console.log(usage());
      return;
    }
    const result = await smokeDeployment(config);
    console.log(`deployment smoke ok: ${result.url} ${result.query} matches=${result.matchCount}`);
  } catch (error) {
    console.error(`deployment smoke failed: ${error instanceof Error ? error.message : error}`);
    process.exit(1);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}
