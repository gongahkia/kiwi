import { describe, expect, it } from "vitest";

import { decryptToken } from "./token-encryption.js";
import {
  buildSlackInstallUrl,
  createSlackOAuthState,
  exchangeSlackOAuthCode,
  parseSlackTeamWatTeamMap,
  slackInstallRecordFromOAuthResponse,
  verifySlackOAuthState
} from "./slack-oauth.js";

describe("Slack OAuth helpers", () => {
  it("builds an install URL with scoped bot and user permissions", () => {
    const state = createSlackOAuthState("state-secret", 1_700_000_000_000, "nonce");
    const url = buildSlackInstallUrl(
      {
        clientId: "123.456",
        redirectUri: "https://wat.example.com/slack/oauth/callback"
      },
      state
    );

    expect(url.origin).toBe("https://slack.com");
    expect(url.pathname).toBe("/oauth/v2/authorize");
    expect(url.searchParams.get("client_id")).toBe("123.456");
    expect(url.searchParams.get("scope")).toBe(
      "commands,chat:write,app_mentions:read,users:read.email"
    );
    expect(url.searchParams.get("user_scope")).toBe("identity.basic,identity.email");
    expect(url.searchParams.get("redirect_uri")).toBe(
      "https://wat.example.com/slack/oauth/callback"
    );
    expect(url.searchParams.get("state")).toBe(state);
  });

  it("rejects tampered and expired states", () => {
    const state = createSlackOAuthState("state-secret", 1_700_000_000_000, "nonce");

    expect(verifySlackOAuthState(state, "state-secret", 1_700_000_001_000)).toMatchObject({
      nonce: "nonce"
    });
    expect(() => verifySlackOAuthState(`${state}x`, "state-secret", 1_700_000_001_000)).toThrow(
      "invalid Slack OAuth state"
    );
    expect(() => verifySlackOAuthState(state, "state-secret", 1_700_000_700_001)).toThrow(
      "expired Slack OAuth state"
    );
  });

  it("encrypts OAuth tokens and maps Slack teams to wat teams", () => {
    const record = slackInstallRecordFromOAuthResponse(
      {
        access_token: "xoxb-token",
        app_id: "A_WAT",
        authed_user: {
          access_token: "xoxp-token",
          id: "U_INSTALLER",
          scope: "identity.basic,identity.email",
          token_type: "user"
        },
        bot_user_id: "U_BOT",
        ok: true,
        scope: "commands,chat:write",
        team: { id: "T_WAT", name: "Wat Workspace" }
      },
      {
        slackTeamWatTeamMap: { T_WAT: "team_wat" },
        tokenEncryptionKey: "enc-key"
      },
      1_700_000_000_000
    );

    expect(record).toMatchObject({
      appId: "A_WAT",
      botScopes: ["commands", "chat:write"],
      botUserId: "U_BOT",
      installerSlackUserId: "U_INSTALLER",
      slackTeamId: "T_WAT",
      slackTeamName: "Wat Workspace",
      userScopes: ["identity.basic", "identity.email"],
      watTeamId: "team_wat"
    });
    expect(decryptToken(record.botToken, "enc-key")).toBe("xoxb-token");
    expect(record.userToken ? decryptToken(record.userToken, "enc-key") : null).toBe("xoxp-token");
  });

  it("exchanges OAuth code with Slack", async () => {
    const fetchOAuth: typeof fetch = async (input, init) => {
      expect(input).toBe("https://slack.com/api/oauth.v2.access");
      expect(init?.method).toBe("POST");
      expect(String(init?.body)).toContain("code=abc");
      return new Response(
        JSON.stringify({
          access_token: "xoxb-token",
          app_id: "A_WAT",
          authed_user: { id: "U_INSTALLER" },
          bot_user_id: "U_BOT",
          ok: true,
          scope: "commands",
          team: { id: "T_WAT", name: "Wat Workspace" }
        })
      );
    };

    const record = await exchangeSlackOAuthCode(
      {
        clientId: "client-id",
        clientSecret: "client-secret",
        slackTeamWatTeamMap: { T_WAT: "team_wat" },
        tokenEncryptionKey: "enc-key"
      },
      "abc",
      fetchOAuth,
      1_700_000_000_000
    );

    expect(record.slackTeamId).toBe("T_WAT");
    expect(decryptToken(record.botToken, "enc-key")).toBe("xoxb-token");
  });

  it("parses explicit Slack workspace mappings", () => {
    expect(parseSlackTeamWatTeamMap("T1:team_1,T2=team_2")).toEqual({
      T1: "team_1",
      T2: "team_2"
    });
    expect(() => parseSlackTeamWatTeamMap("bad")).toThrow(
      "WAT_SLACK_TEAM_MAP must use T123:team_123 pairs"
    );
  });
});
