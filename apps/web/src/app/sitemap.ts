import type { MetadataRoute } from "next";

import { getPublicCorpusEntries } from "@/lib/public-corpus";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
  const entries = await getPublicCorpusEntries();

  return [
    {
      url: siteUrl,
      lastModified: new Date()
    },
    ...entries.map((entry) => ({
      url: `${siteUrl}/term/${entry.id}`,
      lastModified: new Date(entry.updated_at)
    }))
  ];
}
