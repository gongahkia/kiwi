"use client";

import { KeyRound, Plus, Trash2 } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import type { ApiKeyRecord, ApiKeyScope, CreatedApiKey } from "@/lib/api-keys";

interface ApiKeysPanelProps {
  initialKeys: ApiKeyRecord[];
}

const scopes: ApiKeyScope[] = ["search", "suggest", "write", "admin"];

export function ApiKeysPanel({ initialKeys }: ApiKeysPanelProps) {
  const [keys, setKeys] = useState(initialKeys);
  const [name, setName] = useState("Team API key");
  const [selectedScopes, setSelectedScopes] = useState<ApiKeyScope[]>([
    "search",
    "suggest",
    "write"
  ]);
  const [createdKey, setCreatedKey] = useState<CreatedApiKey | null>(null);
  const [error, setError] = useState("");

  function toggleScope(scope: ApiKeyScope) {
    setSelectedScopes((current) =>
      current.includes(scope) ? current.filter((item) => item !== scope) : [...current, scope]
    );
  }

  async function createKey() {
    setError("");
    const response = await fetch("/team/admin/api-keys/api", {
      body: JSON.stringify({ name, scopes: selectedScopes }),
      headers: { "content-type": "application/json", "x-wat-same-origin": "1" },
      method: "POST"
    });
    const payload = (await response.json().catch(() => null)) as {
      key?: CreatedApiKey;
      message?: string;
    } | null;
    if (!response.ok || !payload?.key) {
      setError(payload?.message ?? "create failed");
      return;
    }
    setCreatedKey(payload.key);
    setKeys((current) => [payload.key!, ...current]);
  }

  async function revoke(id: string) {
    if (!window.confirm(`Revoke API key ${id}?`)) return;
    setError("");
    const response = await fetch(
      `/team/admin/api-keys/api?id=${encodeURIComponent(id)}&confirm=${encodeURIComponent(id)}`,
      {
        headers: { "x-wat-same-origin": "1" },
        method: "DELETE"
      }
    );
    const payload = (await response.json().catch(() => null)) as {
      key?: ApiKeyRecord;
      message?: string;
    } | null;
    if (!response.ok || !payload?.key) {
      setError(payload?.message ?? "revoke failed");
      return;
    }
    setKeys((current) => current.map((key) => (key.id === id ? payload.key! : key)));
  }

  return (
    <section className="grid gap-5">
      <div className="grid gap-3 rounded-md border border-input p-4">
        <div className="flex items-center gap-2">
          <KeyRound className="size-4 text-foreground/60" />
          <h2 className="text-lg font-semibold">Create key</h2>
        </div>
        <input
          className="h-10 rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
          onChange={(event) => setName(event.target.value)}
          value={name}
        />
        <div className="flex flex-wrap gap-2">
          {scopes.map((scope) => (
            <button
              className="rounded-md border border-input px-3 py-2 text-sm data-[active=true]:border-primary data-[active=true]:text-primary"
              data-active={selectedScopes.includes(scope)}
              key={scope}
              onClick={() => toggleScope(scope)}
              type="button"
            >
              {scope}
            </button>
          ))}
        </div>
        <Button onClick={createKey} type="button">
          <Plus />
          Create key
        </Button>
        {createdKey ? (
          <div className="grid gap-1 rounded-md border border-input bg-secondary p-3 text-sm">
            <p className="font-medium">New key</p>
            <code className="break-all rounded bg-background px-2 py-1 text-xs">
              {createdKey.key}
            </code>
          </div>
        ) : null}
        {error ? <p className="text-sm text-primary">{error}</p> : null}
      </div>
      <div className="overflow-x-auto rounded-md border border-input">
        <table className="w-full border-collapse text-left text-sm">
          <thead className="bg-secondary">
            <tr>
              <th className="px-3 py-2 font-medium">Name</th>
              <th className="px-3 py-2 font-medium">Prefix</th>
              <th className="px-3 py-2 font-medium">Scopes</th>
              <th className="px-3 py-2 font-medium">Status</th>
              <th className="px-3 py-2 font-medium">Action</th>
            </tr>
          </thead>
          <tbody>
            {keys.map((key) => (
              <tr className="border-t border-input" key={key.id}>
                <td className="px-3 py-2">{key.name}</td>
                <td className="px-3 py-2 font-mono text-xs">{key.key_prefix}...</td>
                <td className="px-3 py-2">{key.scopes.join(", ")}</td>
                <td className="px-3 py-2">{key.revoked_at ? "revoked" : "active"}</td>
                <td className="px-3 py-2">
                  {!key.revoked_at ? (
                    <Button
                      onClick={() => revoke(key.id)}
                      size="sm"
                      type="button"
                      variant="outline"
                    >
                      <Trash2 />
                      Revoke
                    </Button>
                  ) : null}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
