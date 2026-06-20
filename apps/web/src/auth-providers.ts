import type { NextAuthOptions } from "next-auth";
import EmailProvider from "next-auth/providers/email";
import GoogleProvider from "next-auth/providers/google";
import SlackProvider from "next-auth/providers/slack";

export function createAuthProviders(
  env: Record<string, string | undefined> = process.env
): NextAuthOptions["providers"] {
  const providers: NextAuthOptions["providers"] = [
    EmailProvider({
      from: env.EMAIL_FROM ?? "wat@localhost",
      server: env.EMAIL_SERVER ?? "smtp://localhost:1025"
    })
  ];

  if (env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET) {
    providers.push(
      GoogleProvider({
        clientId: env.GOOGLE_CLIENT_ID,
        clientSecret: env.GOOGLE_CLIENT_SECRET
      })
    );
  }

  if (env.SLACK_CLIENT_ID && env.SLACK_CLIENT_SECRET) {
    providers.push(
      SlackProvider({
        authorization: {
          params: { scope: "identity.basic identity.email identity.team" }
        },
        clientId: env.SLACK_CLIENT_ID,
        clientSecret: env.SLACK_CLIENT_SECRET
      })
    );
  }

  return providers;
}
