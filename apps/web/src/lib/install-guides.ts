import { Box, Cable, Code2, Globe, MessageSquare, type LucideIcon } from "lucide-react";

export interface InstallStep {
  body: string;
  code?: string;
  title: string;
}

export interface InstallGuide {
  detail: string;
  environment: string;
  href: string;
  icon: LucideIcon;
  id: string;
  role: string;
  steps: InstallStep[];
  title: string;
}

export const installGuides: InstallGuide[] = [
  {
    detail: "Run the web app locally or point users at the hosted/self-hosted URL.",
    environment: "Local dev or self-host web runtime",
    href: "/install/web",
    icon: Globe,
    id: "web",
    role: "Developers and team admins",
    title: "Web",
    steps: [
      {
        title: "Install workspace dependencies",
        body: "Use the repo root so workspace packages resolve correctly.",
        code: "corepack enable\npnpm install"
      },
      {
        title: "Build and run the web app",
        body: "The app serves public search and admin pages from the same Next.js surface.",
        code: "pnpm --filter @wat/web build\npnpm dev"
      },
      {
        title: "Open the app",
        body: "Use the local URL for search, admin, personal entries, and install paths.",
        code: "open http://localhost:3000"
      }
    ]
  },
  {
    detail: "Build the browser extension and configure API URL, user, team, and token.",
    environment: "Chrome-compatible developer build or enterprise policy install",
    href: "/install/extension",
    icon: Globe,
    id: "extension",
    role: "End users and extension admins",
    title: "Browser Extension",
    steps: [
      {
        title: "Build extension assets",
        body: "The extension currently ships as a developer build until signed store releases land.",
        code: "pnpm --filter @wat/ext build\npnpm --filter @wat/ext zip"
      },
      {
        title: "Configure runtime settings",
        body: "Set the API base URL, account email, API token, optional team ID, and domain filters.",
        code: "WAT_API_BASE_URL=http://localhost:3000\nWAT_API_KEY=<self-host-dev-key>\nWAT_TEAM_ID=team_123"
      },
      {
        title: "Verify lookup",
        body: "Open a technical docs page, select or hover a term, and confirm sourced results appear."
      }
    ]
  },
  {
    detail: "Run the Slack scaffold, verify request signing, and route commands to wat API.",
    environment: "Slack app dev workspace plus local HTTP or socket mode runtime",
    href: "/install/slack",
    icon: MessageSquare,
    id: "slack",
    role: "Workspace admins",
    title: "Slack",
    steps: [
      {
        title: "Build and test the Slack package",
        body: "This validates handlers, signature checks, and current contract tests.",
        code: "pnpm --filter @wat/slack build\npnpm --filter @wat/slack test"
      },
      {
        title: "Set Slack and wat environment",
        body: "Use Slack signing credentials plus the wat API URL, token, and team ID.",
        code: "SLACK_SIGNING_SECRET=<secret>\nWAT_API_BASE_URL=http://localhost:3000\nWAT_API_KEY=<self-host-dev-key>\nWAT_TEAM_ID=team_123"
      },
      {
        title: "Start HTTP mode",
        body: "Expose the local URL with a tunnel when testing real Slack events.",
        code: "pnpm --filter @wat/slack start"
      }
    ]
  },
  {
    detail: "Connect local agent clients to the stdio MCP server for lookup/list/suggest tools.",
    environment: "Local MCP-compatible client",
    href: "/install/mcp",
    icon: Cable,
    id: "mcp",
    role: "Developers configuring agent tools",
    title: "MCP",
    steps: [
      {
        title: "Build the MCP server",
        body: "The npm package is not published yet, so run from a clone.",
        code: "pnpm --filter @wat/mcp build"
      },
      {
        title: "Configure client command",
        body: "Point Claude Desktop/Cursor-compatible clients at the built stdio entrypoint.",
        code: "node apps/mcp/dist/index.js"
      },
      {
        title: "Set hosted/self-host credentials",
        body: "Pass the same wat API key and team ID used by other integration surfaces.",
        code: "WAT_API_KEY=<self-host-dev-key>\nWAT_TEAM_ID=team_123"
      }
    ]
  },
  {
    detail: "Use REST endpoints directly for search, contemporaries, and custom entry writes.",
    environment: "Server-side integration or trusted automation",
    href: "/install/api",
    icon: Code2,
    id: "api",
    role: "Integration developers",
    title: "API",
    steps: [
      {
        title: "Read with anonymous search",
        body: "Public lookups work without credentials.",
        code: "curl 'http://localhost:3000/api/v1/search?q=API&limit=2'"
      },
      {
        title: "Attach self-host/dev credentials for scoped traffic",
        body: "Team and personal overlays use the configured key plus user/team headers until DB-backed per-team keys land.",
        code: 'curl \\\n  -H "Authorization: Bearer $WAT_API_KEY" \\\n  -H "X-Wat-User-Id: user_123" \\\n  -H "X-Wat-Team-Id: team_123" \\\n  \'http://localhost:3000/api/v1/search?q=CAP&limit=5\''
      },
      {
        title: "Track request IDs",
        body: "Send or capture X-Request-Id for support and log correlation."
      }
    ]
  },
  {
    detail: "Run web, Postgres, Mailpit, and Slack scaffold with Docker Compose.",
    environment: "Local or private self-host environment",
    href: "/install/self-host",
    icon: Box,
    id: "self-host",
    role: "Operators",
    title: "Self-host",
    steps: [
      {
        title: "Generate secrets",
        body: "Create stable auth, API, and token-encryption secrets before exposing team data.",
        code: "./scripts/generate-secrets.sh"
      },
      {
        title: "Start Compose",
        body: "Compose starts Postgres, Mailpit, web, and Slack services.",
        code: "docker compose up --build"
      },
      {
        title: "Verify services",
        body: "Check readiness and a public search smoke test.",
        code: "curl -f 'http://localhost:3000/readyz'\ncurl -f 'http://localhost:3000/api/v1/search?q=API&limit=1'"
      }
    ]
  }
];

export function installGuideById(id: string): InstallGuide | null {
  return installGuides.find((guide) => guide.id === id) ?? null;
}
