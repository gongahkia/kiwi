import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import test from "node:test";

const chart = "charts/wat";

function runHelm(args) {
  const result = spawnSync("helm", args, { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout;
}

function failHelm(args) {
  const result = spawnSync("helm", args, { encoding: "utf8" });
  assert.notEqual(result.status, 0);
  return `${result.stderr}\n${result.stdout}`;
}

test("wat Helm chart lints and renders default stack", () => {
  runHelm(["lint", chart]);
  const rendered = runHelm(["template", "wat", chart]);

  assert.match(rendered, /name: wat-auth/);
  assert.match(rendered, /name: wat-postgres/);
  assert.match(rendered, /name: AUTH_SECRET/);
  assert.match(rendered, /app\.kubernetes\.io\/component: postgres/);
});

test("wat Helm chart renders external Postgres and ingress", () => {
  const rendered = runHelm([
    "template",
    "wat",
    chart,
    "--set",
    "postgres.enabled=false",
    "--set",
    "postgres.existingSecret=wat-db",
    "--set",
    "postgres.secretKeys.databaseUrl=DATABASE_URL",
    "--set",
    "auth.existingSecret=wat-auth-existing",
    "--set",
    "ingress.enabled=true",
    "--set",
    "ingress.className=nginx",
    "--set",
    "ingress.hosts[0].host=wat.example.com",
    "--set",
    "web.env.NEXT_PUBLIC_SITE_URL=https://wat.example.com"
  ]);

  assert.doesNotMatch(rendered, /app\.kubernetes\.io\/component: postgres/);
  assert.doesNotMatch(rendered, /name: wat-auth\n/);
  assert.match(rendered, /name: wat-db/);
  assert.match(rendered, /key: DATABASE_URL/);
  assert.match(rendered, /name: wat-auth-existing/);
  assert.match(rendered, /kind: Ingress/);
  assert.match(rendered, /ingressClassName: "nginx"/);
  assert.match(rendered, /host: "wat\.example\.com"/);
});

test("wat Helm chart requires external Postgres secret when disabled", () => {
  const output = failHelm(["template", "wat", chart, "--set", "postgres.enabled=false"]);

  assert.match(output, /postgres\.existingSecret is required when postgres\.enabled=false/);
});
