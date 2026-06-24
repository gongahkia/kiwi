import type { NextConfig } from "next";

import { securityHeaderRules } from "./src/lib/security-headers";

const nextConfig: NextConfig = {
  async headers() {
    return securityHeaderRules();
  },
  output: "standalone",
  outputFileTracingIncludes: {
    "/api/v1/search": [
      "../../packages/ingest/seeds/manual.json",
      "../../data/deltas/2026-06-23/contemporaries-seed.json"
    ]
  }
};

export default nextConfig;
