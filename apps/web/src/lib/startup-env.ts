export type StartupEnv = Record<string, string | undefined> & {
  AUTH_SECRET?: string;
  AUTH_TOKEN_ENCRYPTION_KEY?: string;
  DATABASE_URL?: string;
  EMAIL_FROM?: string;
  EMAIL_SERVER?: string;
  GOOGLE_CLIENT_ID?: string;
  GOOGLE_CLIENT_SECRET?: string;
  NEXTAUTH_SECRET?: string;
  NEXT_PHASE?: string;
  NEXT_PUBLIC_SITE_URL?: string;
  NODE_ENV?: string;
  SLACK_CLIENT_ID?: string;
  SLACK_CLIENT_SECRET?: string;
  WAT_DATABASE_URL?: string;
  WAT_VALIDATE_ENV?: string;
};

export type StartupEnvIssue = {
  action: string;
  key: string;
  message: string;
};

const weakSecrets = new Set([
  "changeme",
  "change-me",
  "change_me",
  "dev",
  "development",
  "password",
  "secret",
  "test",
  "wat"
]);

function value(env: StartupEnv, key: keyof StartupEnv): string {
  return env[key]?.trim() ?? "";
}

function isExplicitlyEnabled(setting: string): boolean {
  return setting === "1" || setting.toLowerCase() === "true";
}

function isExplicitlyDisabled(setting: string): boolean {
  return setting === "0" || setting.toLowerCase() === "false";
}

export function shouldValidateStartupEnv(env: StartupEnv = process.env): boolean {
  const override = value(env, "WAT_VALIDATE_ENV");
  if (override && isExplicitlyEnabled(override)) return true;
  if (override && isExplicitlyDisabled(override)) return false;
  return env.NODE_ENV === "production" && env.NEXT_PHASE !== "phase-production-build";
}

function weakSecret(secret: string): boolean {
  const normalized = secret.trim().toLowerCase();
  return (
    secret.length < 32 ||
    weakSecrets.has(normalized) ||
    normalized.includes("change-me") ||
    normalized.includes("changeme")
  );
}

function issue(key: string, message: string, action: string): StartupEnvIssue {
  return { action, key, message };
}

function validateSecret(
  issues: StartupEnvIssue[],
  key: string,
  secret: string,
  action: string
): void {
  if (!secret) {
    issues.push(issue(key, "missing", action));
    return;
  }
  if (weakSecret(secret)) issues.push(issue(key, "unsafe placeholder or too short", action));
}

function validateDatabaseUrl(env: StartupEnv, issues: StartupEnvIssue[]): void {
  const databaseUrl = value(env, "WAT_DATABASE_URL") || value(env, "DATABASE_URL");
  if (!databaseUrl) {
    issues.push(
      issue(
        "DATABASE_URL",
        "missing",
        "Set DATABASE_URL or WAT_DATABASE_URL to the production Postgres DSN."
      )
    );
    return;
  }

  try {
    const url = new URL(databaseUrl);
    if (url.protocol !== "postgres:" && url.protocol !== "postgresql:") {
      issues.push(
        issue("DATABASE_URL", "must use postgres:// or postgresql://", "Use a Postgres DSN.")
      );
    }
    if (!url.password || url.password === "wat") {
      issues.push(
        issue(
          "DATABASE_URL",
          "missing or unsafe database password",
          "Use a non-default DB user password."
        )
      );
    }
  } catch {
    issues.push(issue("DATABASE_URL", "invalid URL", "Use a valid Postgres DSN."));
  }
}

function validateSiteUrl(env: StartupEnv, issues: StartupEnvIssue[]): void {
  const siteUrl = value(env, "NEXT_PUBLIC_SITE_URL");
  if (!siteUrl) {
    issues.push(
      issue(
        "NEXT_PUBLIC_SITE_URL",
        "missing",
        "Set NEXT_PUBLIC_SITE_URL to the HTTPS public origin."
      )
    );
    return;
  }

  try {
    const url = new URL(siteUrl);
    if (url.protocol !== "https:") {
      issues.push(
        issue("NEXT_PUBLIC_SITE_URL", "must use HTTPS", "Set NEXT_PUBLIC_SITE_URL to https://...")
      );
    }
    if (url.hostname === "localhost" || url.hostname === "127.0.0.1") {
      issues.push(
        issue(
          "NEXT_PUBLIC_SITE_URL",
          "must not point at localhost in production",
          "Set NEXT_PUBLIC_SITE_URL to the deployed public hostname."
        )
      );
    }
  } catch {
    issues.push(issue("NEXT_PUBLIC_SITE_URL", "invalid URL", "Use an absolute HTTPS URL."));
  }
}

function validateEmail(env: StartupEnv, issues: StartupEnvIssue[]): void {
  const emailServer = value(env, "EMAIL_SERVER");
  const emailFrom = value(env, "EMAIL_FROM");

  if (!emailServer || emailServer.includes("localhost")) {
    issues.push(
      issue(
        "EMAIL_SERVER",
        "missing or points at localhost",
        "Set EMAIL_SERVER to the production SMTP connection string."
      )
    );
  }
  if (!emailFrom || emailFrom === "wat@localhost") {
    issues.push(
      issue(
        "EMAIL_FROM",
        "missing or default sender",
        "Set EMAIL_FROM to a verified production sender."
      )
    );
  }
}

function validateProviderPair(
  env: StartupEnv,
  issues: StartupEnvIssue[],
  clientIdKey: keyof StartupEnv,
  clientSecretKey: keyof StartupEnv,
  provider: string
): void {
  const clientId = value(env, clientIdKey);
  const clientSecret = value(env, clientSecretKey);
  if (clientId && !clientSecret) {
    issues.push(
      issue(
        String(clientSecretKey),
        "missing",
        `Set ${String(clientSecretKey)} for ${provider} login.`
      )
    );
  }
  if (!clientId && clientSecret) {
    issues.push(
      issue(String(clientIdKey), "missing", `Set ${String(clientIdKey)} for ${provider} login.`)
    );
  }
}

export function validateProductionEnv(env: StartupEnv): StartupEnvIssue[] {
  const issues: StartupEnvIssue[] = [];
  const authSecret = value(env, "AUTH_SECRET") || value(env, "NEXTAUTH_SECRET");
  const oauthConfigured =
    (value(env, "GOOGLE_CLIENT_ID") && value(env, "GOOGLE_CLIENT_SECRET")) ||
    (value(env, "SLACK_CLIENT_ID") && value(env, "SLACK_CLIENT_SECRET"));

  validateDatabaseUrl(env, issues);
  validateSecret(
    issues,
    "AUTH_SECRET",
    authSecret,
    "Set AUTH_SECRET or NEXTAUTH_SECRET to a generated 32+ character value."
  );
  validateSiteUrl(env, issues);
  validateEmail(env, issues);
  validateProviderPair(env, issues, "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "Google");
  validateProviderPair(env, issues, "SLACK_CLIENT_ID", "SLACK_CLIENT_SECRET", "Slack");
  if (oauthConfigured) {
    validateSecret(
      issues,
      "AUTH_TOKEN_ENCRYPTION_KEY",
      value(env, "AUTH_TOKEN_ENCRYPTION_KEY"),
      "Set AUTH_TOKEN_ENCRYPTION_KEY to a generated 32+ character value before enabling OAuth login."
    );
  }

  return issues;
}

export function validateStartupEnv(env: StartupEnv = process.env): StartupEnvIssue[] {
  return shouldValidateStartupEnv(env) ? validateProductionEnv(env) : [];
}

export function formatStartupEnvError(issues: StartupEnvIssue[]): string {
  return [
    "Invalid wat startup environment:",
    ...issues.map((item) => `- ${item.key}: ${item.message}. ${item.action}`)
  ].join("\n");
}

export function assertValidStartupEnv(env: StartupEnv = process.env): void {
  const issues = validateStartupEnv(env);
  if (issues.length) throw new Error(formatStartupEnvError(issues));
}
