import {
  Box,
  Cable,
  Code2,
  Globe,
  Hash,
  MessageSquare,
  MessagesSquare,
  type LucideIcon
} from "lucide-react";

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
    detail: "Run the primary Slack app and route commands, shortcuts, and mentions to wat API.",
    environment: "Slack dev workspace plus Socket Mode runtime",
    href: "/install/slack",
    icon: MessageSquare,
    id: "slack",
    role: "Workspace admins",
    title: "Slack",
    steps: [
      {
        title: "Build and test the Slack package",
        body: "This validates handlers, signature checks, auth headers, and current contract tests.",
        code: "pnpm --filter @wat/slack build\npnpm --filter @wat/slack test"
      },
      {
        title: "Set Slack and wat environment",
        body: "Use Slack Socket Mode credentials plus the wat API URL, token, team map, and metrics token.",
        code: "SLACK_SOCKET_MODE=true\nSLACK_APP_TOKEN=<xapp-token>\nSLACK_BOT_TOKEN=<xoxb-token>\nSLACK_CLIENT_ID=<client-id>\nSLACK_CLIENT_SECRET=<client-secret>\nSLACK_SIGNING_SECRET=<secret>\nSLACK_REDIRECT_URI=https://wat.example.com/slack/oauth/callback\nSLACK_STATE_SECRET=<random-secret>\nSLACK_TOKEN_ENCRYPTION_KEY=<random-secret>\nSLACK_INSTALL_STORE=postgres\nSLACK_DATABASE_URL=<postgres-url>\nSLACK_METRICS_TOKEN=<random-secret>\nWAT_API_BASE_URL=http://localhost:3000\nWAT_API_KEY=<self-host-dev-key>\nWAT_SLACK_TEAM_MAP=T123:team_123"
      },
      {
        title: "Start Slack runtime",
        body: "HTTP mode serves health and URL verification; Socket Mode handles app interactions.",
        code: "pnpm --filter @wat/slack start"
      },
      {
        title: "Install into Slack",
        body: "Open the install endpoint, complete Slack OAuth, and verify an encrypted install record is stored.",
        code: "open http://localhost:3001/slack/install"
      },
      {
        title: "Prepare directory review",
        body: "Use the Slack manifest and marketplace checklist to configure commands, events, uninstall handling, support links, and the review demo.",
        code: "apps/slack/slack-manifest.yaml\napps/slack/assets/marketplace-checklist.md"
      }
    ]
  },
  {
    detail: "Install the API-based Teams message extension for compose-box glossary search.",
    environment: "Microsoft 365 tenant plus Teams Developer Portal or Agents Toolkit",
    href: "/install/teams",
    icon: MessagesSquare,
    id: "teams",
    role: "Microsoft 365 admins",
    title: "Microsoft Teams",
    steps: [
      {
        title: "Validate the Teams app package",
        body: "This checks the manifest, OpenAPI operation, response template, and required icon dimensions.",
        code: "pnpm --filter @wat/teams test"
      },
      {
        title: "Set wat API fallback team",
        body: "Use the single-team fallback until DB-backed Teams tenant mapping or Entra SSO lands.",
        code: "WAT_API_KEY=<self-host-dev-key>\nWAT_TEAM_ID=team_123"
      },
      {
        title: "Configure package placeholders",
        body: "Render the package with the wat host, Teams app ID, and Teams API secret registration ID.",
        code: "TEAMS_PUBLIC_ORIGIN=https://wat.example.com\nTEAMS_APP_ID=<teams-app-guid>\nTEAMS_API_SECRET_REGISTRATION_ID=<secret-registration-guid>\npnpm --filter @wat/teams package:prod"
      },
      {
        title: "Upload and test search",
        body: "Upload through Teams Developer Portal or Agents Toolkit, then search from compose or command box.",
        code: "apps/teams/dist/wat-teams-app.zip"
      },
      {
        title: "Register tenant mapping",
        body: "Use this when a gateway or later SSO/bot flow can supply X-Wat-Teams-Tenant-Id.",
        code: 'curl -X POST "$WAT_API_BASE_URL/api/v1/teams/installations" \\\n  -H "Authorization: Bearer $WAT_API_KEY" \\\n  -H "Content-Type: application/json" \\\n  -H "X-Wat-Team-Id: team_123" \\\n  --data \'{"microsoft_tenant_id":"tenant_123","app_id":"teams-app-id","auth_type":"apiSecretServiceAuth"}\''
      }
    ]
  },
  {
    detail: "Run Discord signed interactions for slash and message-command glossary workflows.",
    environment: "Discord application plus public HTTPS interactions endpoint",
    href: "/install/discord",
    icon: Hash,
    id: "discord",
    role: "Discord server admins",
    title: "Discord",
    steps: [
      {
        title: "Build and test the Discord package",
        body: "This validates Ed25519 signature checks, PING/PONG, command handlers, stores, and command registration payloads.",
        code: "pnpm --filter @wat/discord build\npnpm --filter @wat/discord test"
      },
      {
        title: "Set Discord and wat environment",
        body: "Use the Discord application public key, bot token for registration, wat API credentials, and a DB-backed guild map.",
        code: "DISCORD_PUBLIC_KEY=<application-public-key>\nDISCORD_APPLICATION_ID=<application-id>\nDISCORD_BOT_TOKEN=<bot-token>\nDISCORD_INSTALL_SCOPES=applications.commands\nDISCORD_INSTALL_STORE=postgres\nDISCORD_DATABASE_URL=<postgres-url>\nDISCORD_METRICS_TOKEN=<random-secret>\nWAT_API_BASE_URL=https://wat.example.com\nWAT_API_KEY=<self-host-dev-key>\nWAT_DISCORD_GUILD_MAP=<guild-id>:team_123"
      },
      {
        title: "Register Discord commands",
        body: "Use a guild ID for fast staging updates; omit it for global production command registration.",
        code: "DISCORD_GUILD_ID=<guild-id> pnpm --filter @wat/discord commands:register"
      },
      {
        title: "Start Discord runtime",
        body: "Set the Discord Interactions Endpoint URL to this runtime before enabling commands.",
        code: "pnpm --filter @wat/discord start\n# https://wat-discord.example.com/discord/interactions\n# https://wat-discord.example.com/discord/install"
      },
      {
        title: "Register guild mapping",
        body: "Use this when installing a Discord server into a wat team; admin roles can use /wat-define.",
        code: 'curl -X POST "$WAT_API_BASE_URL/api/v1/discord/installations" \\\n  -H "Authorization: Bearer $WAT_API_KEY" \\\n  -H "Content-Type: application/json" \\\n  -H "X-Wat-Team-Id: team_123" \\\n  --data \'{"discord_guild_id":"guild_123","guild_name":"Example Guild","application_id":"discord-app-id","admin_role_ids":["role_admin"]}\''
      }
    ]
  },
  {
    detail: "Run API, auth, admin, review, and install pages. Keep this out of the core user loop.",
    environment: "Local dev or self-host API/admin runtime",
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
        body: "The app serves API, auth, admin, review, and support pages from the same Next.js surface.",
        code: "pnpm --filter @wat/web build\npnpm dev"
      },
      {
        title: "Open the app",
        body: "Use the local URL for admin, review, personal entries, and install paths.",
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
    detail:
      "Connect agent clients to wat MCP using local stdio today or the hosted/self-host URL shape once remote MCP is deployed.",
    environment: "Local MCP-compatible client; hosted/self-host remote MCP target",
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
        title: "Configure local stdio clients",
        body: "Point Claude Desktop or Cursor at the built entrypoint and pass the same key as each tool call api_key.",
        code: '{\n  "mcpServers": {\n    "wat": {\n      "command": "node",\n      "args": ["/absolute/path/to/wat/apps/mcp/dist/index.js"],\n      "env": {\n        "WAT_API_KEY": "wat_team_key",\n        "WAT_TEAM_ID": "team_123",\n        "WAT_TEAM_DOMAINS": "example.com"\n      }\n    }\n  }\n}'
      },
      {
        title: "Plan hosted or self-host remote config",
        body: "Use the wat MCP URL plus a scoped team key when remote MCP support is deployed.",
        code: '{\n  "mcpServers": {\n    "wat": {\n      "type": "http",\n      "url": "https://wat.example.com/mcp",\n      "headers": {\n        "Authorization": "Bearer wat_live_read_key",\n        "X-Wat-Team-Id": "team_123"\n      }\n    }\n  }\n}'
      },
      {
        title: "Choose key scope and team behavior",
        body: "Use read keys for lookup/list tools and suggestion-write keys for suggest_definition; team ID labels current stdio responses and should be derived from the key in hosted mode."
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
    detail: "Run web, Postgres, Mailpit, and Slack runtime with Docker Compose.",
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
        body: "Compose starts Postgres, Mailpit, web, and Slack services. Socket Mode remains disabled unless Slack tokens are supplied.",
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
