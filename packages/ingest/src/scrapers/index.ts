import type { ScraperPlugin } from "../scraper.js";
import { dEdgeFossAcronymsScraper } from "./d-edge-foss-acronyms.js";
import { exampleScraper } from "./example.js";
import { kubernetesGlossaryScraper } from "./kubernetes-glossary.js";

export const scrapers = new Map<string, ScraperPlugin>([
  [dEdgeFossAcronymsScraper.name, dEdgeFossAcronymsScraper],
  [exampleScraper.name, exampleScraper],
  [kubernetesGlossaryScraper.name, kubernetesGlossaryScraper]
]);
