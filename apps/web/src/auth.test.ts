import { describe, expect, it } from "vitest";

import { createAuthProviders } from "./auth-providers";
import { isPublicEmailDomain } from "./lib/next-auth-adapter";

describe("createAuthProviders", () => {
  it("always includes email auth", () => {
    const providers = createAuthProviders({});

    expect(providers.map((provider) => provider.id)).toEqual(["email"]);
  });

  it("adds Google when OAuth credentials are configured", () => {
    const providers = createAuthProviders({
      GOOGLE_CLIENT_ID: "google-client",
      GOOGLE_CLIENT_SECRET: "google-secret"
    });

    expect(providers.map((provider) => provider.id)).toEqual(["email", "google"]);
  });

  it("adds Slack when OAuth credentials are configured", () => {
    const providers = createAuthProviders({
      SLACK_CLIENT_ID: "slack-client",
      SLACK_CLIENT_SECRET: "slack-secret"
    });

    expect(providers.map((provider) => provider.id)).toEqual(["email", "slack"]);
  });

  it("does not add partially configured OAuth providers", () => {
    const providers = createAuthProviders({
      GOOGLE_CLIENT_ID: "google-client",
      SLACK_CLIENT_SECRET: "slack-secret"
    });

    expect(providers.map((provider) => provider.id)).toEqual(["email"]);
  });
});

describe("public email domain guardrail", () => {
  it("blocks consumer email domains from auto-created teams", () => {
    expect(isPublicEmailDomain("gmail.com")).toBe(true);
    expect(isPublicEmailDomain("Outlook.com")).toBe(true);
    expect(isPublicEmailDomain("icloud.com")).toBe(true);
  });

  it("allows organization domains to use email-domain team claim", () => {
    expect(isPublicEmailDomain("example.com")).toBe(false);
    expect(isPublicEmailDomain("engineering.example")).toBe(false);
  });
});
