import type {
  App,
  SlackCommandMiddlewareArgs,
  SlackEventMiddlewareArgs,
  SlackShortcutMiddlewareArgs
} from "@slack/bolt";

export const explainAcronymsShortcutId = "wat_explain_acronyms";

interface WatBoltDeps {
  fetchLookup?: typeof fetch;
  fetchWrite?: typeof fetch;
  slackAdminUserIds?: string[];
  watApiBaseUrl: string;
}

interface SlackTextObject {
  text: string;
  type: "mrkdwn" | "plain_text";
}

interface SlackBlock {
  accessory?: {
    action_id: string;
    text: SlackTextObject;
    type: "button";
    value: string;
  };
  block_id?: string;
  elements?: Array<{
    action_id: string;
    text: SlackTextObject;
    type: "button";
    value: string;
  }>;
  text?: SlackTextObject;
  type: "actions" | "section";
}

interface SearchEntry {
  expansions?: string[];
  id?: string;
  meaning_short?: string;
  term?: string;
}

interface SearchResponse {
  matches?: Array<{ entry?: SearchEntry }>;
}

interface SlackMessage {
  blocks: SlackBlock[];
  response_type?: "ephemeral" | "in_channel";
  text: string;
  thread_ts?: string;
}

export function registerWatBoltHandlers(
  app: Pick<App, "command" | "event" | "shortcut">,
  deps: WatBoltDeps
): void {
  app.command("/wat", async (args) => {
    await handleWatCommand(args, deps);
  });

  app.command("/wat-define", async (args) => {
    await handleDefineCommand(args, deps);
  });

  app.command("/wat-suggest", async (args) => {
    await handleSuggestCommand(args, deps);
  });

  app.shortcut({ callback_id: explainAcronymsShortcutId, type: "message_action" }, async (args) => {
    await handleExplainAcronymsShortcut(args, deps);
  });

  app.event("app_mention", async (args) => {
    await handleAppMention(args, deps);
  });
}

async function handleWatCommand(args: SlackCommandMiddlewareArgs, deps: WatBoltDeps) {
  await args.ack();
  const term = args.command.text.trim();
  if (!term) {
    await args.respond({
      response_type: "ephemeral",
      text: "Use `/wat <term>`."
    });
    return;
  }

  const result = await lookup(deps, term, args.command.channel_name);
  await args.respond(renderLookupMessage(term, result, { response_type: "ephemeral" }));
}

async function handleDefineCommand(args: SlackCommandMiddlewareArgs, deps: WatBoltDeps) {
  await args.ack();
  if (!isAdminUser(args.command.user_id, deps)) {
    await args.respond({
      response_type: "ephemeral",
      text: "Only configured Slack workspace admins can define team entries."
    });
    return;
  }

  const definition = parseDefinition(args.command.text, fallbackMeaning(args.command.user_name));
  if (!definition) {
    await args.respond({
      response_type: "ephemeral",
      text: "Use `/wat-define <term> as <expansion> -- <meaning>`."
    });
    return;
  }

  await writeJson(deps, "/team/admin/entries/api", teamEntryFromCommand(definition, args.command));
  await args.respond({
    response_type: "ephemeral",
    text: `Defined ${definition.term} as ${definition.expansion}.`
  });
}

async function handleSuggestCommand(args: SlackCommandMiddlewareArgs, deps: WatBoltDeps) {
  await args.ack();
  const definition = parseDefinition(args.command.text, fallbackMeaning(args.command.user_name));
  if (!definition) {
    await args.respond({
      response_type: "ephemeral",
      text: "Use `/wat-suggest <term> as <expansion> -- <meaning>`."
    });
    return;
  }

  await writeJson(deps, "/suggest/api", {
    domains: domainsFor(args.command),
    expansion: definition.expansion,
    meaning: definition.meaning,
    source_url: slackSourceUrl(args.command),
    term: definition.term
  });
  await args.respond({
    response_type: "ephemeral",
    text: `Suggested ${definition.term} as ${definition.expansion} for admin review.`
  });
}

async function handleExplainAcronymsShortcut(args: SlackShortcutMiddlewareArgs, deps: WatBoltDeps) {
  await args.ack();
  const messageText =
    "message" in args.shortcut && typeof args.shortcut.message.text === "string"
      ? args.shortcut.message.text
      : "";
  const terms = acronymsIn(messageText);
  if (terms.length === 0) {
    await args.respond({
      response_type: "ephemeral",
      text: "No acronyms found."
    });
    return;
  }

  const lookups = await Promise.all(terms.map((term) => lookup(deps, term, messageText)));
  await args.respond(renderAcronymList(lookups));
}

async function handleAppMention(args: SlackEventMiddlewareArgs<"app_mention">, deps: WatBoltDeps) {
  const text = "text" in args.event && typeof args.event.text === "string" ? args.event.text : "";
  const term = text.replace(/<@[^>]+>/g, " ").trim();
  if (!term || !("say" in args)) return;

  const result = await lookup(deps, term, text);
  const threadTs = "thread_ts" in args.event ? args.event.thread_ts : args.event.ts;
  await args.say({
    ...renderLookupMessage(term, result),
    thread_ts: threadTs
  });
}

function acronymsIn(text: string): string[] {
  return Array.from(new Set(text.match(/\b[A-Z][A-Z0-9]{1,9}\b/g) ?? [])).slice(0, 8);
}

async function writeJson(deps: WatBoltDeps, pathname: string, body: unknown): Promise<void> {
  const client = deps.fetchWrite ?? fetch;
  const url = new URL(pathname, deps.watApiBaseUrl);
  const response = await client(url, {
    body: JSON.stringify(body),
    headers: { "content-type": "application/json" },
    method: "POST"
  });
  if (!response.ok) throw new Error(`wat write failed: ${response.status}`);
}

async function lookup(deps: WatBoltDeps, term: string, context = ""): Promise<SearchEntry[]> {
  const client = deps.fetchLookup ?? fetch;
  const url = new URL("/api/v1/search", deps.watApiBaseUrl);
  url.searchParams.set("q", term);
  url.searchParams.set("limit", "5");
  if (context.trim()) url.searchParams.set("context", context.trim());

  const response = await client(url);
  if (!response.ok) throw new Error(`wat lookup failed: ${response.status}`);
  const body = (await response.json()) as SearchResponse;
  return body.matches?.flatMap((match) => (match.entry ? [match.entry] : [])) ?? [];
}

interface ParsedDefinition {
  expansion: string;
  meaning: string;
  term: string;
}

function parseDefinition(text: string, defaultMeaning: string): ParsedDefinition | null {
  const match = text
    .trim()
    .match(/^([A-Za-z][A-Za-z0-9.-]{1,32})\s+as\s+(.+?)(?:\s+(?:--|because)\s+(.+))?$/i);
  if (!match?.[1] || !match[2]) return null;

  return {
    expansion: match[2].trim(),
    meaning: match[3]?.trim() || defaultMeaning,
    term: match[1].trim().toUpperCase()
  };
}

function teamEntryFromCommand(
  definition: ParsedDefinition,
  command: SlackCommandMiddlewareArgs["command"]
) {
  return {
    domains: domainsFor(command),
    expansion: definition.expansion,
    id: `slack-${(command.team_id ?? "team").toLowerCase()}-${definition.term.toLowerCase()}`,
    meaning: definition.meaning,
    sources: [
      {
        license: "proprietary-team",
        publisher: command.team_domain ?? "Slack",
        retrieved_at: new Date().toISOString(),
        snippet: definition.meaning,
        title: `Slack /wat-define by ${command.user_name}`,
        url: slackSourceUrl(command)
      }
    ],
    term: definition.term
  };
}

function domainsFor(command: SlackCommandMiddlewareArgs["command"]): string[] {
  return [command.team_domain, command.channel_name].filter(
    (value): value is string => typeof value === "string" && value.trim().length > 0
  );
}

function fallbackMeaning(userName: string): string {
  return `Defined from Slack by ${userName}.`;
}

function isAdminUser(userId: string, deps: WatBoltDeps): boolean {
  return deps.slackAdminUserIds?.includes(userId) ?? false;
}

function slackSourceUrl(command: SlackCommandMiddlewareArgs["command"]): string {
  return `https://slack.com/app_redirect?channel=${encodeURIComponent(command.channel_id)}`;
}

function renderLookupMessage(
  term: string,
  entries: SearchEntry[],
  options: Pick<SlackMessage, "response_type"> = {}
): SlackMessage {
  const [top, ...rest] = entries;
  if (!top) {
    return {
      ...options,
      blocks: [section(`No result for *${term}*.`)],
      text: `No result for ${term}.`
    };
  }

  const title = `${top.term ?? term}: ${top.expansions?.[0] ?? term}`;
  const summary = top.meaning_short ? `\n${top.meaning_short}` : "";
  const blocks = [section(`*${title}*${summary}`)];
  const buttons = rest.slice(0, 4).map((entry) => ({
    action_id: "wat_disambiguate",
    text: { text: entry.term ?? "Result", type: "plain_text" as const },
    type: "button" as const,
    value: entry.id ?? entry.term ?? "result"
  }));
  if (buttons.length > 0) blocks.push({ elements: buttons, type: "actions" as const });

  return {
    ...options,
    blocks,
    text: title
  };
}

function renderAcronymList(lookups: SearchEntry[][]): SlackMessage {
  const entries = lookups.flatMap((matches) => matches.slice(0, 1));
  if (entries.length === 0) {
    return {
      blocks: [section("No glossary matches found.")],
      response_type: "ephemeral",
      text: "No glossary matches found."
    };
  }

  const lines = entries.map((entry) => `*${entry.term}*: ${entry.expansions?.[0] ?? entry.term}`);
  return {
    blocks: [section(lines.join("\n"))],
    response_type: "ephemeral",
    text: entries.map((entry) => `${entry.term}: ${entry.expansions?.[0] ?? entry.term}`).join("\n")
  };
}

function section(text: string): SlackBlock {
  return {
    text: {
      text,
      type: "mrkdwn"
    },
    type: "section"
  };
}
