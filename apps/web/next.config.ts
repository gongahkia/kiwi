import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  outputFileTracingIncludes: {
    "/api/v1/search": ["../../packages/ingest/seeds/manual.json"]
  }
};

export default nextConfig;
