import { defineConfig } from "drizzle-kit";

export default defineConfig({
  casing: "snake_case",
  dialect: "postgresql",
  out: "./drizzle",
  schema: "./src/schema.ts"
});
