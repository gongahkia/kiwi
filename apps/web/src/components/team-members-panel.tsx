"use client";

import { MailPlus, Trash2 } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import type { TeamInvite } from "@/lib/team-invites";
import type { TeamMember, TeamRole } from "@/lib/team-members";

interface TeamMembersPanelProps {
  initialInvites: TeamInvite[];
  initialMembers: TeamMember[];
}

const roles: TeamRole[] = ["member", "admin"];

export function TeamMembersPanel({ initialInvites, initialMembers }: TeamMembersPanelProps) {
  const [members, setMembers] = useState(initialMembers);
  const [invites, setInvites] = useState(initialInvites);
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<TeamRole>("member");
  const [error, setError] = useState("");
  const [createdToken, setCreatedToken] = useState("");

  async function invite() {
    setError("");
    setCreatedToken("");
    const response = await fetch("/team/admin/members/api", {
      body: JSON.stringify({ email, role }),
      headers: { "content-type": "application/json", "x-wat-same-origin": "1" },
      method: "POST"
    });
    const payload = (await response.json().catch(() => null)) as {
      invite?: TeamInvite & { token?: string };
      message?: string;
    } | null;
    if (!response.ok || !payload?.invite) {
      setError(payload?.message ?? "invite failed");
      return;
    }
    setInvites((current) => [payload.invite!, ...current]);
    setCreatedToken(payload.invite.token ?? "");
    setEmail("");
  }

  async function updateRole(id: string, nextRole: TeamRole) {
    setError("");
    const response = await fetch("/team/admin/members/api", {
      body: JSON.stringify({ id, role: nextRole }),
      headers: { "content-type": "application/json", "x-wat-same-origin": "1" },
      method: "PATCH"
    });
    const payload = (await response.json().catch(() => null)) as {
      member?: TeamMember;
      message?: string;
    } | null;
    if (!response.ok || !payload?.member) {
      setError(payload?.message ?? "role update failed");
      return;
    }
    setMembers((current) => current.map((item) => (item.id === id ? payload.member! : item)));
  }

  async function remove(id: string) {
    if (!window.confirm(`Remove member ${id}?`)) return;
    setError("");
    const response = await fetch(
      `/team/admin/members/api?id=${encodeURIComponent(id)}&confirm=${encodeURIComponent(id)}`,
      {
        headers: { "x-wat-same-origin": "1" },
        method: "DELETE"
      }
    );
    const payload = (await response.json().catch(() => null)) as {
      member?: TeamMember;
      message?: string;
    } | null;
    if (!response.ok || !payload?.member) {
      setError(payload?.message ?? "remove failed");
      return;
    }
    setMembers((current) => current.filter((item) => item.id !== id));
  }

  return (
    <section className="grid gap-5">
      <div className="grid gap-3 rounded-md border border-input p-4">
        <h2 className="text-lg font-semibold">Invite member</h2>
        <div className="grid gap-2 sm:grid-cols-[1fr_10rem_auto]">
          <input
            className="h-10 rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onChange={(event) => setEmail(event.target.value)}
            placeholder="teammate@example.com"
            type="email"
            value={email}
          />
          <select
            className="h-10 rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onChange={(event) => setRole(event.target.value as TeamRole)}
            value={role}
          >
            {roles.map((item) => (
              <option key={item} value={item}>
                {item}
              </option>
            ))}
          </select>
          <Button onClick={invite} type="button">
            <MailPlus />
            Invite
          </Button>
        </div>
        {createdToken ? (
          <code className="break-all rounded-md border border-input bg-secondary p-3 text-xs">
            {createdToken}
          </code>
        ) : null}
        {error ? <p className="text-sm text-primary">{error}</p> : null}
      </div>

      <div className="overflow-x-auto rounded-md border border-input">
        <table className="w-full border-collapse text-left text-sm">
          <thead className="bg-secondary">
            <tr>
              <th className="px-3 py-2 font-medium">Email</th>
              <th className="px-3 py-2 font-medium">Role</th>
              <th className="px-3 py-2 font-medium">Action</th>
            </tr>
          </thead>
          <tbody>
            {members.map((member) => (
              <tr className="border-t border-input" key={member.id}>
                <td className="px-3 py-2">{member.email}</td>
                <td className="px-3 py-2">
                  <select
                    className="h-9 rounded-md border border-input bg-background px-2"
                    onChange={(event) => updateRole(member.id, event.target.value as TeamRole)}
                    value={member.role}
                  >
                    {roles.map((item) => (
                      <option key={item} value={item}>
                        {item}
                      </option>
                    ))}
                  </select>
                </td>
                <td className="px-3 py-2">
                  <Button
                    onClick={() => remove(member.id)}
                    size="sm"
                    type="button"
                    variant="outline"
                  >
                    <Trash2 />
                    Remove
                  </Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="overflow-x-auto rounded-md border border-input">
        <table className="w-full border-collapse text-left text-sm">
          <thead className="bg-secondary">
            <tr>
              <th className="px-3 py-2 font-medium">Pending invite</th>
              <th className="px-3 py-2 font-medium">Role</th>
              <th className="px-3 py-2 font-medium">Expires</th>
            </tr>
          </thead>
          <tbody>
            {invites.map((invite) => (
              <tr className="border-t border-input" key={invite.id}>
                <td className="px-3 py-2">{invite.email}</td>
                <td className="px-3 py-2">{invite.role}</td>
                <td className="px-3 py-2 tabular-nums">{invite.expires_at.slice(0, 10)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
