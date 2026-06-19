import type { ScraperPlugin } from "../scraper.js";
import { exampleScraper } from "./example.js";

export const scrapers = new Map<string, ScraperPlugin>([[exampleScraper.name, exampleScraper]]);
