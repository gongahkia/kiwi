import type {
  App,
  SlackCommandMiddlewareArgs,
  SlackEventMiddlewareArgs,
  SlackShortcutMiddlewareArgs
} from "@slack/bolt";

export const explainAcronymsShortcutId = "wat_explain_acronyms";

interface WatBoltDeps {
  fetchLookup?: typeof fetch;
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
