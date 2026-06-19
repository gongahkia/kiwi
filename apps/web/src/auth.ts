import type { NextAuthOptions } from "next-auth";
import EmailProvider from "next-auth/providers/email";

import { watNextAuthAdapter } from "@/lib/next-auth-adapter";

export const authOptions: NextAuthOptions = {
  adapter: watNextAuthAdapter(),
  callbacks: {
    session({ session, user }) {
      const watUser = user as typeof user & {
        role?: "admin" | "member";
        teamId?: string | null;
      };
      if (session.user) {
        session.user.id = user.id;
        session.user.role = watUser.role ?? null;
        session.user.teamId = watUser.teamId ?? null;
      }
      return session;
    }
  },
  pages: {
    signIn: "/login",
    verifyRequest: "/login?check=email"
  },
  providers: [
    EmailProvider({
      from: process.env.EMAIL_FROM ?? "wat@localhost",
      server: process.env.EMAIL_SERVER ?? "smtp://localhost:1025"
    })
  ],
  secret: process.env.AUTH_SECRET ?? process.env.NEXTAUTH_SECRET,
  session: {
    strategy: "database"
  }
};
