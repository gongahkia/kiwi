#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const requiredFlyTokens = {
  "infra/fly/README.md": [
    "apps/slack/Dockerfile",
    "slack_app_name",
    "slack_image",
    "slack_signing_secret",
    "slack_token_encryption_key"
  ],
  "infra/fly/main.tf": [
    'resource "fly_app" "slack"',
    'resource "fly_machine" "slack"',
    'resource "fly_secrets" "slack"',
    "SLACK_HTTP_MODE",
    "SLACK_SIGNING_SECRET",
    "SLACK_INSTALL_STORE",
    "WAT_API_BASE_URL",
    'path     = "/healthz"'
  ],
  "infra/fly/outputs.tf": ['output "slack_url"'],
  "infra/fly/variables.tf": [
    'variable "slack_app_name"',
    'variable "slack_image"',
    'variable "slack_signing_secret"',
    'variable "slack_token_encryption_key"',
    'variable "slack_wat_api_key"'
  ]
};

export function validateFlyConfig(files) {
  const missing = [];
  for (const [path, tokens] of Object.entries(requiredFlyTokens)) {
    const text = files[path] ?? "";
    for (const token of tokens) {
      if (!text.includes(token)) missing.push(`${path}: ${token}`);
    }
  }
  return { missing, ok: missing.length === 0 };
}

function main() {
  const files = Object.fromEntries(
    Object.keys(requiredFlyTokens).map((path) => [path, readFileSync(path, "utf8")])
  );
  const result = validateFlyConfig(files);
  if (!result.ok) {
    for (const item of result.missing) console.error(`missing Fly config token: ${item}`);
    process.exit(1);
  }
  console.log("Fly config ok");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
