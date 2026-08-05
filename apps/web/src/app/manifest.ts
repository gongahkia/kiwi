import type { MetadataRoute } from "next";

import { webManifest } from "@/lib/pwa";

export default function manifest(): MetadataRoute.Manifest {
  return webManifest;
}
