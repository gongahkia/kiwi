import type { ScraperPlugin } from "../scraper.js";
import { dEdgeFossAcronymsScraper } from "./d-edge-foss-acronyms.js";
import { exampleScraper } from "./example.js";
import { jargonFileScraper } from "./jargon-file.js";
import { kubernetesGlossaryScraper } from "./kubernetes-glossary.js";
import { postgresqlGlossaryScraper } from "./postgresql-glossary.js";

export const scrapers = new Map<string, ScraperPlugin>([
  [dEdgeFossAcronymsScraper.name, dEdgeFossAcronymsScraper],
  [exampleScraper.name, exampleScraper],
  [jargonFileScraper.name, jargonFileScraper],
  [kubernetesGlossaryScraper.name, kubernetesGlossaryScraper],
  [postgresqlGlossaryScraper.name, postgresqlGlossaryScraper]
]);
