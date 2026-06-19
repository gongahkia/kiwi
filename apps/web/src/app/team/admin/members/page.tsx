import Link from "next/link";

import { getTeamMembers } from "@/lib/team-members";

export default function TeamMembersPage() {
  const members = getTeamMembers();

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-4xl gap-6">
        <header className="grid gap-2">
          <Link
            className="text-sm text-foreground/65 underline-offset-4 hover:underline"
            href="/team/admin"
          >
            Team dashboard
          </Link>
          <h1 className="text-4xl font-semibold">Team members</h1>
        </header>
        <div className="overflow-x-auto rounded-md border border-input">
          <table className="w-full border-collapse text-left text-sm">
            <thead className="bg-secondary">
              <tr>
                <th className="px-3 py-2 font-medium">Email</th>
                <th className="px-3 py-2 font-medium">Role</th>
              </tr>
            </thead>
            <tbody>
              {members.map((member) => (
                <tr className="border-t border-input" key={member.id}>
                  <td className="px-3 py-2">{member.email}</td>
                  <td className="px-3 py-2">{member.role}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </main>
  );
}
