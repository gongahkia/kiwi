import type { MetadataRoute } from "next";

export const webManifest = {
  background_color: "#ffffff",
  categories: ["business", "productivity", "utilities"],
  description: "Layered glossary lookup for public, team, and personal acronyms.",
  display: "standalone",
  icons: [
    {
      purpose: "any",
      sizes: "any",
      src: "/icon.svg",
      type: "image/svg+xml"
    },
    {
      purpose: "maskable",
      sizes: "any",
      src: "/icon.svg",
      type: "image/svg+xml"
    }
  ],
  id: "/",
  name: "wat",
  orientation: "portrait-primary",
  scope: "/",
  short_name: "wat",
  start_url: "/",
  theme_color: "#ffffff"
} satisfies MetadataRoute.Manifest;
