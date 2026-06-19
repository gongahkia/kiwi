import type { ScraperPlugin } from "../scraper.js";
import { dEdgeFossAcronymsScraper } from "./d-edge-foss-acronyms.js";
import { exampleScraper } from "./example.js";

export const scrapers = new Map<string, ScraperPlugin>([
  [dEdgeFossAcronymsScraper.name, dEdgeFossAcronymsScraper],
  [exampleScraper.name, exampleScraper]
]);
