export interface TeamAdminChecklistInput {
  memberCount: number;
  teamEntryCount: number;
}

export interface TeamAdminChecklistItem {
  complete: boolean;
  href: string;
  label: string;
  nextAction: string;
}

export function teamAdminChecklist({
  memberCount,
  teamEntryCount
}: TeamAdminChecklistInput): TeamAdminChecklistItem[] {
  return [
    {
      complete: teamEntryCount > 0,
      href: "/team/admin/import",
      label: "Import acronyms",
      nextAction: "Upload JSON or CSV"
    },
    {
      complete: memberCount > 1,
      href: "/team/admin/members",
      label: "Invite members",
      nextAction: "Add teammates"
    },
    {
      complete: false,
      href: "/install/extension",
      label: "Install extension",
      nextAction: "Open extension setup"
    },
    {
      complete: false,
      href: "/install/slack",
      label: "Connect Slack",
      nextAction: "Open Slack setup"
    }
  ];
}
