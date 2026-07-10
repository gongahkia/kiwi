import type {
  App,
  SlackCommandMiddlewareArgs,
  SlackEventMiddlewareArgs,
  SlackShortcutMiddlewareArgs
} from "@slack/bolt";

import {
  checkSlackRateLimit,
  defaultRateLimitStore,
  workspaceRateLimitConfigFromEnv,
  type SlackRateLimitStore,
  type SlackRateLimitSubject,
  type WorkspaceRateLimitConfig,
  type WorkspaceRateLimitDecision
} from "./workspace-rate-limit.js";
import type { SlackInstallStore } from "./slack-install-store.js";
import type { SlackMonitor } from "./slack-monitoring.js";

export const explainAcronymsShortcutId = "wat_explain_acronyms";

export interface WatBoltDeps {
  fetchAdminCheck?: typeof fetch;
  fetchLookup?: typeof fetch;
  fetchSlackUser?: typeof fetch;
  fetchWrite?: typeof fetch;
  installStore?: SlackInstallStore;
  monitor?: SlackMonitor;
  rateLimitConfig?: WorkspaceRateLimitConfig;
  rateLimitStore?: SlackRateLimitStore;
  slackAdminUserIds?: string[];
  slackBotToken?: string;
  slackTeamWatTeamMap?: Record<string, string>;
  watApiKey?: string;
  watApiBaseUrl: string;
  watTeamId?: string;
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
  contemporaries?: string[];
  expansions?: string[];
  id?: string;
  meaning_short?: string;
  term?: string;
}

interface SearchResponse {
  matches?: Array<{ entry?: SearchEntry }>;
}

interface SlackUserInfoResponse {
  ok?: boolean;
  user?: {
    is_admin?: boolean;
    is_owner?: boolean;
    profile?: {
      email?: string;
    };
  };
}

interface AdminCheckResponse {
  admin?: boolean;
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

  app.command("/wat-alt", async (args) => {
    await handleWatAltCommand(args, deps);
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
  deps.monitor?.increment("wat_slack_command_total", { command: "/wat" });
  if (!(await allowCommand(args, deps))) return;
  const term = args.command.text.trim();
  if (!term) {
    await args.respond({
      response_type: "ephemeral",
      text: "Use `/wat <term>`."
    });
    return;
  }

  const watTeamId = await resolveWatTeamId(deps, commandSlackTeamId(args.command));
  const result = await lookup(
    deps,
    term,
    args.command.channel_name,
    args.command.user_id,
    watTeamId
  );
  await args.respond(renderLookupMessage(term, result, { response_type: "ephemeral" }));
}

async function handleWatAltCommand(args: SlackCommandMiddlewareArgs, deps: WatBoltDeps) {
  await args.ack();
  deps.monitor?.increment("wat_slack_command_total", { command: "/wat-alt" });
  if (!(await allowCommand(args, deps))) return;
  const term = args.command.text.trim();
  if (!term) {
    await args.respond({
      response_type: "ephemeral",
      text: "Use `/wat-alt <term>`."
    });
    return;
  }

  const watTeamId = await resolveWatTeamId(deps, commandSlackTeamId(args.command));
  const entries = await lookup(
    deps,
    term,
    args.command.channel_name,
    args.command.user_id,
    watTeamId
  );
  const top = entries[0];
  const alternatives = listAlternatives(top?.contemporaries);
  const resolved = await Promise.all(
    alternatives.map((alternative) =>
      lookup(deps, alternative, args.command.channel_name, args.command.user_id, watTeamId)
    )
  );
  await args.respond(
    renderAlternativesMessage(term, top, alternatives, resolved, { response_type: "ephemeral" })
  );
}

async function handleDefineCommand(args: SlackCommandMiddlewareArgs, deps: WatBoltDeps) {
  await args.ack();
  deps.monitor?.increment("wat_slack_command_total", { command: "/wat-define" });
  if (!(await allowCommand(args, deps))) return;
  const watTeamId = await resolveWatTeamId(deps, commandSlackTeamId(args.command));
  if (!watTeamId) {
    await args.respond({
      response_type: "ephemeral",
      text: "Slack workspace is not mapped to a wat team."
    });
    return;
  }
  if (!(await isAdminUser(args.command.user_id, deps, watTeamId))) {
    await args.respond({
      response_type: "ephemeral",
      text: "Only wat team admins can define team entries from Slack."
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

  await writeJson(
    deps,
    "/api/v1/custom-entries",
    customEntryFromCommand(definition, args.command),
    args.command.user_id,
    watTeamId
  );
  await args.respond({
    response_type: "ephemeral",
    text: `Defined ${escapeSlackText(definition.term)} as ${escapeSlackText(definition.expansion)}.`
  });
}

async function handleSuggestCommand(args: SlackCommandMiddlewareArgs, deps: WatBoltDeps) {
  await args.ack();
  deps.monitor?.increment("wat_slack_command_total", { command: "/wat-suggest" });
  if (!(await allowCommand(args, deps))) return;
  const watTeamId = await resolveWatTeamId(deps, commandSlackTeamId(args.command));
  if (!watTeamId) {
    await args.respond({
      response_type: "ephemeral",
      text: "Slack workspace is not mapped to a wat team."
    });
    return;
  }
  const definition = parseDefinition(args.command.text, fallbackMeaning(args.command.user_name));
  if (!definition) {
    await args.respond({
      response_type: "ephemeral",
      text: "Use `/wat-suggest <term> as <expansion> -- <meaning>`."
    });
    return;
  }

  await writeJson(
    deps,
    "/api/v1/suggestions",
    {
      domains: domainsFor(args.command),
      expansion: definition.expansion,
      meaning: definition.meaning,
      source_url: slackSourceUrl(args.command),
      term: definition.term
    },
    args.command.user_id,
    watTeamId
  );
  await args.respond({
    response_type: "ephemeral",
    text: `Suggested ${escapeSlackText(definition.term)} as ${escapeSlackText(definition.expansion)} for admin review.`
  });
}

async function handleExplainAcronymsShortcut(args: SlackShortcutMiddlewareArgs, deps: WatBoltDeps) {
  await args.ack();
  if (!(await allowShortcut(args, deps))) return;
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

  const watTeamId = await resolveWatTeamId(deps, shortcutSlackTeamId(args));
  const lookups = await Promise.all(
    terms.map((term) => lookup(deps, term, messageText, args.shortcut.user.id, watTeamId))
  );
  await args.respond(renderAcronymList(lookups));
}

async function handleAppMention(args: SlackEventMiddlewareArgs<"app_mention">, deps: WatBoltDeps) {
  const text = "text" in args.event && typeof args.event.text === "string" ? args.event.text : "";
  const term = text.replace(/<@[^>]+>/g, " ").trim();
  if (!term || !("say" in args)) return;
  const rateLimit = await rateLimitDecision(mentionSubject(args), deps);
  if (!rateLimit.allowed) {
    await args.say({
      text: rateLimitText(rateLimit),
      thread_ts: appMentionThreadTs(args.event)
    });
    return;
  }

  const watTeamId = await resolveWatTeamId(deps, mentionSlackTeamId(args));
  const result = await lookup(deps, term, text, args.event.user, watTeamId);
  const threadTs = appMentionThreadTs(args.event);
  await args.say({
    ...renderLookupMessage(term, result),
    thread_ts: threadTs
  });
}

function acronymsIn(text: string): string[] {
  return Array.from(new Set(text.match(/\b[A-Z][A-Z0-9]{1,9}\b/g) ?? [])).slice(0, 8);
}

async function allowCommand(args: SlackCommandMiddlewareArgs, deps: WatBoltDeps): Promise<boolean> {
  const decision = await rateLimitDecision(commandSubject(args.command), deps);
  if (decision.allowed) return true;

  await args.respond({
    response_type: "ephemeral",
    text: rateLimitText(decision)
  });
  return false;
}

async function allowShortcut(
  args: SlackShortcutMiddlewareArgs,
  deps: WatBoltDeps
): Promise<boolean> {
  const decision = await rateLimitDecision(shortcutSubject(args), deps);
  if (decision.allowed) return true;

  await args.respond({
    response_type: "ephemeral",
    text: rateLimitText(decision)
  });
  return false;
}

function commandSubject(command: SlackCommandMiddlewareArgs["command"]): SlackRateLimitSubject {
  return {
    channelId: command.channel_id,
    userId: command.user_id,
    workspaceId: command.team_id ?? command.team_domain ?? "unknown"
  };
}

function shortcutSubject(args: SlackShortcutMiddlewareArgs): SlackRateLimitSubject {
  return {
    channelId: "channel" in args.shortcut ? args.shortcut.channel.id : undefined,
    userId: args.shortcut.user.id,
    workspaceId: args.shortcut.team?.id ?? args.shortcut.user.team_id ?? "unknown"
  };
}

function mentionSubject(args: SlackEventMiddlewareArgs<"app_mention">): SlackRateLimitSubject {
  return {
    channelId: "channel" in args.event ? args.event.channel : undefined,
    userId: "user" in args.event ? args.event.user : undefined,
    workspaceId:
      "team_id" in args.body && typeof args.body.team_id === "string"
        ? args.body.team_id
        : "unknown"
  };
}

function commandSlackTeamId(command: SlackCommandMiddlewareArgs["command"]): string | undefined {
  return command.team_id ?? undefined;
}

function shortcutSlackTeamId(args: SlackShortcutMiddlewareArgs): string | undefined {
  return args.shortcut.team?.id ?? args.shortcut.user.team_id ?? undefined;
}

function mentionSlackTeamId(args: SlackEventMiddlewareArgs<"app_mention">): string | undefined {
  return "team_id" in args.body && typeof args.body.team_id === "string"
    ? args.body.team_id
    : undefined;
}

async function resolveWatTeamId(
  deps: WatBoltDeps,
  slackTeamId: string | undefined
): Promise<string | undefined> {
  const normalizedSlackTeamId = slackTeamId?.trim();
  if (normalizedSlackTeamId && deps.installStore) {
    const install = await deps.installStore.getBySlackTeamId(normalizedSlackTeamId);
    if (install?.watTeamId) return install.watTeamId;
  }
  if (normalizedSlackTeamId && deps.slackTeamWatTeamMap?.[normalizedSlackTeamId]) {
    return deps.slackTeamWatTeamMap[normalizedSlackTeamId];
  }
  return deps.watTeamId;
}

function appMentionThreadTs(event: SlackEventMiddlewareArgs<"app_mention">["event"]): string {
  return "thread_ts" in event && typeof event.thread_ts === "string"
    ? event.thread_ts
    : (event.ts ?? "");
}

function rateLimitDecision(
  subject: SlackRateLimitSubject,
  deps: WatBoltDeps
): Promise<WorkspaceRateLimitDecision> {
  return checkSlackRateLimit(
    subject,
    deps.rateLimitConfig ?? workspaceRateLimitConfigFromEnv(),
    deps.rateLimitStore ?? defaultRateLimitStore()
  );
}

function rateLimitText(decision: WorkspaceRateLimitDecision): string {
  return `Slack rate limit exceeded for ${decision.scope}. Retry after ${decision.retryAfter}s.`;
}

async function writeJson(
  deps: WatBoltDeps,
  pathname: string,
  body: unknown,
  userId: string,
  watTeamId?: string
): Promise<void> {
  const client = deps.fetchWrite ?? fetch;
  const url = new URL(pathname, deps.watApiBaseUrl);
  const response = await client(url, {
    body: JSON.stringify(body),
    headers: { "content-type": "application/json", ...watAuthHeaders(deps, userId, watTeamId) },
    method: "POST"
  });
  deps.monitor?.increment("wat_slack_write_total", {
    path: pathname,
    status: response.status
  });
  if (!response.ok) throw new Error(`wat write failed: ${response.status}`);
}

async function lookup(
  deps: WatBoltDeps,
  term: string,
  context = "",
  userId?: string,
  watTeamId?: string
): Promise<SearchEntry[]> {
  const client = deps.fetchLookup ?? fetch;
  const url = new URL("/api/v1/search", deps.watApiBaseUrl);
  url.searchParams.set("q", term);
  url.searchParams.set("limit", "5");
  if (context.trim()) url.searchParams.set("context", context.trim());

  const response = await client(url, { headers: watAuthHeaders(deps, userId, watTeamId) });
  deps.monitor?.increment("wat_slack_lookup_total", { status: response.status });
  if (!response.ok) throw new Error(`wat lookup failed: ${response.status}`);
  const body = (await response.json()) as SearchResponse;
  return body.matches?.flatMap((match) => (match.entry ? [match.entry] : [])) ?? [];
}

function watAuthHeaders(
  deps: WatBoltDeps,
  userId?: string,
  watTeamId = deps.watTeamId
): Record<string, string> {
  const headers: Record<string, string> = {};
  if (!deps.watApiKey) return headers;
  headers.authorization = `Bearer ${deps.watApiKey}`;
  if (watTeamId) headers["x-wat-team-id"] = watTeamId;
  if (userId) headers["x-wat-user-id"] = `slack:${userId}`;
  return headers;
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

function customEntryFromCommand(
  definition: ParsedDefinition,
  command: SlackCommandMiddlewareArgs["command"]
) {
  return {
    domains: domainsFor(command),
    expansion: definition.expansion,
    meaning: definition.meaning,
    mode: "upsert",
    scope: "team",
    sourceTitle: `Slack /wat-define by ${command.user_name}`,
    sourceUrl: slackSourceUrl(command),
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

async function isAdminUser(userId: string, deps: WatBoltDeps, watTeamId: string): Promise<boolean> {
  const slackUser = await slackUserInfo(userId, deps);
  const isSlackAdmin =
    deps.slackAdminUserIds?.includes(userId) ||
    slackUser?.isAdmin === true ||
    slackUser?.isOwner === true;
  if (!isSlackAdmin || !slackUser?.email) return false;
  return watAdminCheck(slackUser.email, deps, userId, watTeamId);
}

async function slackUserInfo(
  userId: string,
  deps: WatBoltDeps
): Promise<{ email: string | null; isAdmin: boolean; isOwner: boolean } | null> {
  if (!deps.slackBotToken) return null;
  const client = deps.fetchSlackUser ?? fetch;
  const url = new URL("https://slack.com/api/users.info");
  url.searchParams.set("user", userId);
  const response = await client(url, {
    headers: { authorization: `Bearer ${deps.slackBotToken}` }
  });
  if (!response.ok) return null;
  const body = (await response.json()) as SlackUserInfoResponse;
  if (body.ok !== true) return null;
  return {
    email:
      typeof body.user?.profile?.email === "string" ? body.user.profile.email.trim() || null : null,
    isAdmin: body.user?.is_admin === true,
    isOwner: body.user?.is_owner === true
  };
}

async function watAdminCheck(
  email: string,
  deps: WatBoltDeps,
  userId: string,
  watTeamId: string
): Promise<boolean> {
  if (!deps.watApiKey) return false;
  const client = deps.fetchAdminCheck ?? fetch;
  const url = new URL("/api/v1/team/admin-check", deps.watApiBaseUrl);
  url.searchParams.set("user", email);
  const response = await client(url, { headers: watAuthHeaders(deps, userId, watTeamId) });
  deps.monitor?.increment("wat_slack_admin_check_total", { status: response.status });
  if (!response.ok) return false;
  const body = (await response.json()) as AdminCheckResponse;
  return body.admin === true;
}

function listAlternatives(values?: string[]): string[] {
  const seen = new Set<string>();
  const alternatives: string[] = [];
  for (const value of values ?? []) {
    const alternative = value.trim();
    if (!alternative) continue;
    const key = alternative.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    alternatives.push(alternative);
  }
  return alternatives;
}

function formatAlternativesLine(values?: string[]): string {
  return `Alternatives: ${listAlternatives(values).map(escapeSlackText).join(", ")}`;
}

function escapeSlackText(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
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
  const safeTerm = escapeSlackText(term);
  if (!top) {
    return {
      ...options,
      blocks: [section(`No result for *${safeTerm}*.`)],
      text: `No result for ${safeTerm}.`
    };
  }

  const title = `${escapeSlackText(top.term ?? term)}: ${escapeSlackText(top.expansions?.[0] ?? term)}`;
  const lines = [`*${title}*`];
  if (top.meaning_short) lines.push(escapeSlackText(top.meaning_short));
  if (top.contemporaries && listAlternatives(top.contemporaries).length > 0) {
    lines.push(formatAlternativesLine(top.contemporaries));
  }
  const blocks = [section(lines.join("\n"))];
  const buttons = rest.slice(0, 4).map((entry) => ({
    action_id: "wat_disambiguate",
    text: { text: escapeSlackText(entry.term ?? "Result"), type: "plain_text" as const },
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

function renderAlternativesMessage(
  term: string,
  entry: SearchEntry | undefined,
  alternatives: string[],
  resolved: SearchEntry[][],
  options: Pick<SlackMessage, "response_type"> = {}
): SlackMessage {
  const resolvedTerm = entry?.term ?? term;
  const safeResolvedTerm = escapeSlackText(resolvedTerm);
  const safeTerm = escapeSlackText(term);
  if (!entry) {
    return {
      ...options,
      blocks: [section(`No result for *${safeTerm}*.`)],
      text: `No result for ${safeTerm}.`
    };
  }
  if (alternatives.length === 0) {
    return {
      ...options,
      blocks: [section(`No alternatives for *${safeResolvedTerm}*.`)],
      text: `No alternatives for ${safeResolvedTerm}.`
    };
  }

  const lines = [`Alternatives for *${safeResolvedTerm}*:`];
  for (const [index, alternative] of alternatives.entries()) {
    lines.push(renderAlternativeLine(alternative, resolved[index]?.[0]));
  }
  return {
    ...options,
    blocks: [section(lines.join("\n"))],
    text: `Alternatives for ${safeResolvedTerm}: ${alternatives.map(escapeSlackText).join(", ")}`
  };
}

function renderAlternativeLine(alternative: string, entry: SearchEntry | undefined): string {
  const safeAlternative = escapeSlackText(alternative);
  if (!entry) return `*${safeAlternative}*`;
  const title = `${escapeSlackText(entry.term ?? alternative)}: ${escapeSlackText(entry.expansions?.[0] ?? alternative)}`;
  return entry.meaning_short
    ? `*${title}* - ${escapeSlackText(entry.meaning_short)}`
    : `*${title}*`;
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

  const lines = entries.map((entry) => {
    const term = entry.term ?? "Result";
    return `*${escapeSlackText(term)}*: ${escapeSlackText(entry.expansions?.[0] ?? term)}`;
  });
  return {
    blocks: [section(lines.join("\n"))],
    response_type: "ephemeral",
    text: entries
      .map((entry) => {
        const term = entry.term ?? "Result";
        return `${escapeSlackText(term)}: ${escapeSlackText(entry.expansions?.[0] ?? term)}`;
      })
      .join("\n")
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
