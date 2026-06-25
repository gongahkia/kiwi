import { copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sourceDir = join(root, "appPackage");
const outputDir = join(root, "dist", "appPackage");

const publicOrigin = originFromEnv();
const publicHost = new URL(publicOrigin).host;
const requireProductionConfig = process.env.TEAMS_REQUIRE_PRODUCTION_CONFIG === "true";

await rm(outputDir, { force: true, recursive: true });
await mkdir(outputDir, { recursive: true });

const manifest = JSON.parse(await readFile(join(sourceDir, "manifest.json"), "utf8"));
manifest.id = env("TEAMS_APP_ID", manifest.id);
manifest.version = env("TEAMS_APP_VERSION", manifest.version);
manifest.packageName = env("TEAMS_PACKAGE_NAME", manifest.packageName);
manifest.developer.name = env("TEAMS_DEVELOPER_NAME", manifest.developer.name);
manifest.developer.websiteUrl = publicOrigin;
manifest.developer.privacyUrl = `${publicOrigin}/privacy`;
manifest.developer.termsOfUseUrl = `${publicOrigin}/terms`;
manifest.validDomains = [publicHost];
manifest.composeExtensions[0].authorization.apiSecretServiceAuthConfiguration.apiSecretRegistrationId =
  env(
    "TEAMS_API_SECRET_REGISTRATION_ID",
    manifest.composeExtensions[0].authorization.apiSecretServiceAuthConfiguration
      .apiSecretRegistrationId
  );

if (requireProductionConfig) {
  assert(publicOrigin.startsWith("https://"), "TEAMS_PUBLIC_ORIGIN must be HTTPS");
  assert(
    manifest.id !== "7f503b6e-5710-4fd3-b4d0-8e8c2a0bd3d1",
    "TEAMS_APP_ID must be set for production package"
  );
  assert(
    manifest.composeExtensions[0].authorization.apiSecretServiceAuthConfiguration
      .apiSecretRegistrationId !== "00000000-0000-0000-0000-000000000000",
    "TEAMS_API_SECRET_REGISTRATION_ID must be set for production package"
  );
}

const openApi = (await readFile(join(sourceDir, "wat-openapi.yml"), "utf8")).replaceAll(
  "https://wat.example.com",
  publicOrigin
);

await writeFile(join(outputDir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
await writeFile(join(outputDir, "wat-openapi.yml"), openApi);
await copyFile(
  join(sourceDir, "response-template.json"),
  join(outputDir, "response-template.json")
);
await copyFile(join(sourceDir, "color.png"), join(outputDir, "color.png"));
await copyFile(join(sourceDir, "outline.png"), join(outputDir, "outline.png"));

console.log(`rendered Teams app package to ${outputDir}`);

function env(key, fallback) {
  return process.env[key]?.trim() || fallback;
}

function originFromEnv() {
  const raw = env("TEAMS_PUBLIC_ORIGIN", env("NEXT_PUBLIC_SITE_URL", "https://wat.example.com"));
  const url = new URL(raw);
  url.pathname = "";
  url.search = "";
  url.hash = "";
  return url.toString().replace(/\/$/, "");
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
