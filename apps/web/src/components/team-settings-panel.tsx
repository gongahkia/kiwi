"use client";

import { Save } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import type { TeamProfile } from "@/lib/team-profile";
import type { TeamSettings } from "@/lib/team-settings";

interface TeamSettingsPanelProps {
  initialProfile: TeamProfile;
  initialSettings: TeamSettings;
}

export function TeamSettingsPanel({ initialProfile, initialSettings }: TeamSettingsPanelProps) {
  const [profile, setProfile] = useState(initialProfile);
  const [settings, setSettings] = useState(initialSettings);
  const [domainTags, setDomainTags] = useState(initialSettings.domain_tags.join(", "));
  const [status, setStatus] = useState("");

  async function save() {
    setStatus("");
    const response = await fetch("/team/admin/settings/api", {
      body: JSON.stringify({
        profile,
        settings: {
          ...settings,
          domain_tags: domainTags
            .split(",")
            .map((tag) => tag.trim())
            .filter(Boolean)
        }
      }),
      headers: { "content-type": "application/json", "x-wat-same-origin": "1" },
      method: "POST"
    });
    const payload = (await response.json().catch(() => null)) as {
      message?: string;
      profile?: TeamProfile;
      settings?: TeamSettings;
    } | null;
    if (!response.ok || !payload?.profile || !payload.settings) {
      setStatus(payload?.message ?? "save failed");
      return;
    }
    setProfile(payload.profile);
    setSettings(payload.settings);
    setDomainTags(payload.settings.domain_tags.join(", "));
    setStatus("Saved");
  }

  return (
    <section className="grid gap-4 rounded-md border border-input p-4">
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="grid gap-2 text-sm font-medium">
          Team name
          <input
            className="h-10 rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onChange={(event) =>
              setProfile((current) => ({ ...current, name: event.target.value }))
            }
            value={profile.name}
          />
        </label>
        <label className="grid gap-2 text-sm font-medium">
          Email domain
          <input
            className="h-10 rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onChange={(event) =>
              setProfile((current) => ({ ...current, email_domain: event.target.value }))
            }
            value={profile.email_domain}
          />
        </label>
        <label className="grid gap-2 text-sm font-medium">
          Default domain filter
          <input
            className="h-10 rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onChange={(event) =>
              setSettings((current) => ({
                ...current,
                default_domain_filter: event.target.value
              }))
            }
            value={settings.default_domain_filter}
          />
        </label>
        <label className="grid gap-2 text-sm font-medium">
          Domain tags
          <input
            className="h-10 rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onChange={(event) => setDomainTags(event.target.value)}
            value={domainTags}
          />
        </label>
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input
          checked={settings.allow_public_layer}
          onChange={(event) =>
            setSettings((current) => ({ ...current, allow_public_layer: event.target.checked }))
          }
          type="checkbox"
        />
        Allow public layer
      </label>
      <div className="flex items-center gap-3">
        <Button onClick={save} type="button">
          <Save />
          Save settings
        </Button>
        {status ? <p className="text-sm text-foreground/65">{status}</p> : null}
      </div>
    </section>
  );
}
