import { describe, expect, it } from "vitest";

import {
  assertValidStartupEnv,
  formatStartupEnvError,
  shouldValidateStartupEnv,
  validateProductionEnv,
  validateStartupEnv
} from "./startup-env";

const validProdEnv = {
  AUTH_SECRET: "auth_secret_012345678901234567890123456789",
  DATABASE_URL: "postgres://wat_prod:strong_db_password@db.example.com:5432/wat",
  EMAIL_FROM: "Wat <security@example.com>",
  EMAIL_SERVER: "smtp://smtp.example.com:587",
  NEXT_PUBLIC_SITE_URL: "https://wat.example.com",
  NODE_ENV: "production",
  WAT_API_KEY: "wat_api_key_012345678901234567890123456789"
};

describe("startup env validation", () => {
  it("skips validation outside production runtime by default", () => {
    expect(validateStartupEnv({ NODE_ENV: "development" })).toEqual([]);
    expect(
      validateStartupEnv({ NEXT_PHASE: "phase-production-build", NODE_ENV: "production" })
    ).toEqual([]);
  });

  it("can be explicitly enabled or disabled", () => {
    expect(shouldValidateStartupEnv({ NODE_ENV: "development", WAT_VALIDATE_ENV: "true" })).toBe(
      true
    );
    expect(shouldValidateStartupEnv({ NODE_ENV: "production", WAT_VALIDATE_ENV: "false" })).toBe(
      false
    );
  });

  it("accepts production-safe required values", () => {
    expect(validateStartupEnv(validProdEnv)).toEqual([]);
  });

  it("reports missing and unsafe production values with actions", () => {
    const issues = validateProductionEnv({
      AUTH_SECRET: "change-me",
      DATABASE_URL: "postgres://wat:wat@localhost:5432/wat",
      EMAIL_FROM: "wat@localhost",
      EMAIL_SERVER: "smtp://localhost:1025",
      NEXT_PUBLIC_SITE_URL: "http://localhost:3000",
      WAT_API_KEY: ""
    });

    expect(issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ key: "AUTH_SECRET", message: "unsafe placeholder or too short" }),
        expect.objectContaining({
          key: "DATABASE_URL",
          message: "missing or unsafe database password"
        }),
        expect.objectContaining({ key: "EMAIL_FROM", message: "missing or default sender" }),
        expect.objectContaining({ key: "EMAIL_SERVER", message: "missing or points at localhost" }),
        expect.objectContaining({ key: "NEXT_PUBLIC_SITE_URL", message: "must use HTTPS" }),
        expect.objectContaining({ key: "WAT_API_KEY", message: "missing" })
      ])
    );
    expect(formatStartupEnvError(issues)).toContain("Invalid wat startup environment:");
  });

  it("requires complete optional OAuth provider pairs", () => {
    expect(
      validateProductionEnv({
        ...validProdEnv,
        GOOGLE_CLIENT_ID: "google-client",
        SLACK_CLIENT_SECRET: "slack-secret"
      })
    ).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ key: "GOOGLE_CLIENT_SECRET", message: "missing" }),
        expect.objectContaining({ key: "SLACK_CLIENT_ID", message: "missing" })
      ])
    );
  });

  it("throws a startup error when production env is invalid", () => {
    expect(() => assertValidStartupEnv({ NODE_ENV: "production" })).toThrow(
      "Invalid wat startup environment:"
    );
  });
});
