import type { NextConfig } from "next";

import { nextHeaderRules } from "./src/lib/security-headers";

const nextConfig: NextConfig = {
  generateEtags: true,
  async headers() {
    return nextHeaderRules();
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
