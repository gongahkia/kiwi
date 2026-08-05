import { readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

const appPackage = resolve(process.cwd(), process.argv[2] ?? "appPackage");
const production = process.argv.includes("--production");

const manifestPath = join(appPackage, "manifest.json");
const openApiPath = join(appPackage, "wat-openapi.yml");
const templatePath = join(appPackage, "response-template.json");

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const openApi = readFileSync(openApiPath, "utf8");
const template = JSON.parse(readFileSync(templatePath, "utf8"));

assert(manifest.manifestVersion === "1.17", "manifestVersion must be 1.17");
assert(manifest.description.full.length <= 128, "description.full must be <= 128 chars");

const [composeExtension] = manifest.composeExtensions ?? [];
assert(
  composeExtension?.composeExtensionType === "apiBased",
  "composeExtensionType must be apiBased"
);
assert(
  composeExtension.authorization?.authType === "apiSecretServiceAuth",
  "authType must be apiSecretServiceAuth"
);
assert(
  composeExtension.apiSpecificationFile === "wat-openapi.yml",
  "apiSpecificationFile mismatch"
);
assert(manifest.validDomains?.length === 1, "validDomains must contain one host");
if (production) {
  assert(manifest.developer.websiteUrl.startsWith("https://"), "websiteUrl must be HTTPS");
  assert(
    manifest.id !== "7f503b6e-5710-4fd3-b4d0-8e8c2a0bd3d1",
    "manifest id must not be the checked-in placeholder"
  );
  assert(
    composeExtension.authorization.apiSecretServiceAuthConfiguration.apiSecretRegistrationId !==
      "00000000-0000-0000-0000-000000000000",
    "apiSecretRegistrationId must not be the checked-in placeholder"
  );
}

const [command] = composeExtension.commands ?? [];
assert(command?.id === "searchGlossary", "command id mismatch");
assert(command.type === "query", "command type must be query");
assert(
  command.apiResponseRenderingTemplateFile === "response-template.json",
  "response template mismatch"
);
assert(command.parameters?.length === 1, "Teams API-based commands must use one parameter");
assert(command.parameters[0]?.name === "q", "command parameter must be q");

assert(openApi.includes("/api/v1/teams/search:"), "OpenAPI Teams search path missing");
assert(openApi.includes("operationId: searchGlossary"), "OpenAPI operationId mismatch");
assert(openApi.includes("name: q"), "OpenAPI parameter q missing");
assert(openApi.includes("bearerAuth:"), "OpenAPI bearer auth missing");
assert(openApi.includes("results:"), "OpenAPI Teams results schema missing");

assert(template.version === "1.0", "template version mismatch");
assert(template.jsonPath === "results", "template jsonPath must target results");
assert(template.responseLayout === "list", "template responseLayout must be list");

for (const [name, width, height] of [
  [manifest.icons.color, 192, 192],
  [manifest.icons.outline, 32, 32]
]) {
  const iconPath = join(appPackage, name);
  statSync(iconPath);
  const actual = pngSize(iconPath);
  assert(actual.width === width && actual.height === height, `${name} must be ${width}x${height}`);
}

function pngSize(path) {
  const bytes = readFileSync(path);
  assert(bytes.toString("ascii", 1, 4) === "PNG", `${path} is not PNG`);
  return {
    height: bytes.readUInt32BE(20),
    width: bytes.readUInt32BE(16)
  };
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
