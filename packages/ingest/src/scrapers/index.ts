import type { ScraperPlugin } from "../scraper.js";
import { awsServicesScraper } from "./aws-services.js";
import { azureServicesScraper } from "./azure-services.js";
import { cncfGlossaryScraper } from "./cncf-glossary.js";
import { cncfLandscapeScraper } from "./cncf-landscape.js";
import { cloudServiceComparisonScraper } from "./cloud-service-comparison.js";
import { dEdgeFossAcronymsScraper } from "./d-edge-foss-acronyms.js";
import { gcpServicesScraper } from "./gcp-services.js";
import { exampleScraper } from "./example.js";
import { githubGlossaryScraper } from "./github-glossary.js";
import { ietfRfcIndexScraper } from "./ietf-rfc-index.js";
import { jargonFileScraper } from "./jargon-file.js";
import { kubernetesGlossaryScraper } from "./kubernetes-glossary.js";
import { linuxFoundationGlossaryScraper } from "./linux-foundation-glossary.js";
import { mdnGlossaryScraper } from "./mdn-glossary.js";
import { mdnWebTechnologyScraper } from "./mdn-web-technology.js";
import { nistCsrcGlossaryScraper } from "./nist-csrc-glossary.js";
import { postgresqlExtensionsScraper } from "./postgresql-extensions.js";
import { postgresqlGlossaryScraper } from "./postgresql-glossary.js";
import { w3cGlossaryScraper } from "./w3c-glossary.js";
import { wikipediaAcronymsScraper } from "./wikipedia-acronyms.js";
import { wikipediaOutlineScraper } from "./wikipedia-outline.js";

export const scrapers = new Map<string, ScraperPlugin>([
  [awsServicesScraper.name, awsServicesScraper],
  [azureServicesScraper.name, azureServicesScraper],
  [cncfGlossaryScraper.name, cncfGlossaryScraper],
  [cncfLandscapeScraper.name, cncfLandscapeScraper],
  [cloudServiceComparisonScraper.name, cloudServiceComparisonScraper],
  [dEdgeFossAcronymsScraper.name, dEdgeFossAcronymsScraper],
  [gcpServicesScraper.name, gcpServicesScraper],
  [exampleScraper.name, exampleScraper],
  [githubGlossaryScraper.name, githubGlossaryScraper],
  [ietfRfcIndexScraper.name, ietfRfcIndexScraper],
  [jargonFileScraper.name, jargonFileScraper],
  [kubernetesGlossaryScraper.name, kubernetesGlossaryScraper],
  [linuxFoundationGlossaryScraper.name, linuxFoundationGlossaryScraper],
  [mdnGlossaryScraper.name, mdnGlossaryScraper],
  [mdnWebTechnologyScraper.name, mdnWebTechnologyScraper],
  [nistCsrcGlossaryScraper.name, nistCsrcGlossaryScraper],
  [postgresqlExtensionsScraper.name, postgresqlExtensionsScraper],
  [postgresqlGlossaryScraper.name, postgresqlGlossaryScraper],
  [w3cGlossaryScraper.name, w3cGlossaryScraper],
  [wikipediaAcronymsScraper.name, wikipediaAcronymsScraper],
  [wikipediaOutlineScraper.name, wikipediaOutlineScraper]
]);
