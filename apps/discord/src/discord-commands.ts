export const DISCORD_API_VERSION = "10";

export const DiscordApplicationCommandType = {
  CHAT_INPUT: 1,
  MESSAGE: 3
} as const;

export const DiscordCommandOptionType = {
  STRING: 3
} as const;

export interface DiscordCommandOption {
  description: string;
  max_length?: number;
  min_length?: number;
  name: string;
  required?: boolean;
  type: number;
}

export interface DiscordCommandPayload {
  contexts?: number[];
  default_member_permissions?: string | null;
  description?: string;
  integration_types?: number[];
  name: string;
  options?: DiscordCommandOption[];
  type: number;
}

const guildInstall = [0];
const guildContext = [0];

const termOption: DiscordCommandOption = {
  description: "Acronym or term to look up",
  max_length: 80,
  min_length: 1,
  name: "term",
  required: true,
  type: DiscordCommandOptionType.STRING
};

export const discordCommandPayloads: DiscordCommandPayload[] = [
  {
    contexts: guildContext,
    description: "Look up a wat glossary term",
    integration_types: guildInstall,
    name: "wat",
    options: [termOption],
    type: DiscordApplicationCommandType.CHAT_INPUT
  },
  {
    contexts: guildContext,
    description: "Show alternatives for a glossary term",
    integration_types: guildInstall,
    name: "wat-alt",
    options: [termOption],
    type: DiscordApplicationCommandType.CHAT_INPUT
  },
  {
    contexts: guildContext,
    description: "Suggest a team glossary entry for review",
    integration_types: guildInstall,
    name: "wat-suggest",
    options: [
      termOption,
      {
        description: "Expansion to suggest",
        max_length: 160,
        min_length: 1,
        name: "expansion",
        required: true,
        type: DiscordCommandOptionType.STRING
      },
      {
        description: "Short meaning for the suggestion",
        max_length: 700,
        min_length: 1,
        name: "meaning",
        required: true,
        type: DiscordCommandOptionType.STRING
      }
    ],
    type: DiscordApplicationCommandType.CHAT_INPUT
  },
  {
    contexts: guildContext,
    default_member_permissions: "8",
    description: "Define or update a team glossary entry",
    integration_types: guildInstall,
    name: "wat-define",
    options: [
      termOption,
      {
        description: "Expansion to save",
        max_length: 160,
        min_length: 1,
        name: "expansion",
        required: true,
        type: DiscordCommandOptionType.STRING
      },
      {
        description: "Short meaning to save",
        max_length: 700,
        min_length: 1,
        name: "meaning",
        required: true,
        type: DiscordCommandOptionType.STRING
      }
    ],
    type: DiscordApplicationCommandType.CHAT_INPUT
  },
  {
    contexts: guildContext,
    integration_types: guildInstall,
    name: "Explain acronyms",
    type: DiscordApplicationCommandType.MESSAGE
  }
];

export function discordCommandsJson(): string {
  return `${JSON.stringify(discordCommandPayloads, null, 2)}\n`;
}
