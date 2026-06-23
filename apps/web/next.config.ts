import type { NextConfig } from "next";

import { securityHeaderRules } from "./src/lib/security-headers";

const nextConfig: NextConfig = {
  async headers() {
    return securityHeaderRules();
  },
  output: "standalone",
  outputFileTracingIncludes: {
    "/api/v1/search": ["../../packages/ingest/seeds/manual.json"]
  }
};

export default nextConfig;
