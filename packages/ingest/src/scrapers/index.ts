import type { ScraperPlugin } from "../scraper.js";
import { awsServicesScraper } from "./aws-services.js";
import { azureServicesScraper } from "./azure-services.js";
import { dEdgeFossAcronymsScraper } from "./d-edge-foss-acronyms.js";
import { gcpServicesScraper } from "./gcp-services.js";
import { exampleScraper } from "./example.js";
import { jargonFileScraper } from "./jargon-file.js";
import { kubernetesGlossaryScraper } from "./kubernetes-glossary.js";
import { linuxFoundationGlossaryScraper } from "./linux-foundation-glossary.js";
import { mdnGlossaryScraper } from "./mdn-glossary.js";
import { nistCsrcGlossaryScraper } from "./nist-csrc-glossary.js";
import { postgresqlGlossaryScraper } from "./postgresql-glossary.js";
import { w3cGlossaryScraper } from "./w3c-glossary.js";
import { wikipediaAcronymsScraper } from "./wikipedia-acronyms.js";

export const scrapers = new Map<string, ScraperPlugin>([
  [awsServicesScraper.name, awsServicesScraper],
  [azureServicesScraper.name, azureServicesScraper],
  [dEdgeFossAcronymsScraper.name, dEdgeFossAcronymsScraper],
  [gcpServicesScraper.name, gcpServicesScraper],
  [exampleScraper.name, exampleScraper],
  [jargonFileScraper.name, jargonFileScraper],
  [kubernetesGlossaryScraper.name, kubernetesGlossaryScraper],
  [linuxFoundationGlossaryScraper.name, linuxFoundationGlossaryScraper],
  [mdnGlossaryScraper.name, mdnGlossaryScraper],
  [nistCsrcGlossaryScraper.name, nistCsrcGlossaryScraper],
  [postgresqlGlossaryScraper.name, postgresqlGlossaryScraper],
  [w3cGlossaryScraper.name, w3cGlossaryScraper],
  [wikipediaAcronymsScraper.name, wikipediaAcronymsScraper]
]);
