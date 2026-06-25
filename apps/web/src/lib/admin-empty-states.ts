export interface AdminEmptyStateContent {
  actionHref: string;
  actionLabel: string;
  body: string;
  title: string;
}

export const adminEmptyStates = {
  apiKeys: {
    actionHref: "/install/api",
    actionLabel: "Open API setup",
    body: "Create a team-scoped key before connecting Slack, Teams, Discord, browser, or MCP clients.",
    title: "No API keys"
  },
  members: {
    actionHref: "/install/web",
    actionLabel: "Open web setup",
    body: "Add the invitation flow before production onboarding; local fixtures can still verify role screens.",
    title: "No members"
  },
  suggestions: {
    actionHref: "/",
    actionLabel: "Search glossary",
    body: "No-result suggestions and Slack member suggestions appear here for review.",
    title: "No suggestions"
  },
  teamEntries: {
    actionHref: "/team/admin/import",
    actionLabel: "Import entries",
    body: "Create the first entry with the form, or import a reviewed JSON/CSV glossary.",
    title: "No team entries"
  }
} satisfies Record<string, AdminEmptyStateContent>;
