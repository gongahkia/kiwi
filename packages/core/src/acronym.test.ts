import { describe, expect, it } from "vitest";

import { detectAcronyms } from "./acronym.js";

const terms = [
  "API",
  "SLA",
  "SLO",
  "CAP",
  "REST",
  "HTTP",
  "HTTPS",
  "TCP",
  "UDP",
  "BGP",
  "DNS",
  "TLS",
  "SSL",
  "SSH",
  "CI/CD",
  "CPU",
  "GPU",
  "RAM",
  "SSD",
  "I/O",
  "DB",
  "SQL",
  "DDL",
  "DML",
  "OLTP",
  "OLAP",
  "ETL",
  "ELT",
  "SRE",
  "RCA",
  "MTTR",
  "MTBF",
  "RPO",
  "RTO",
  "IAM",
  "ACL",
  "RBAC",
  "ABAC",
  "JWT",
  "OIDC",
  "OAuth2",
  "SAML",
  "MFA",
  "SSO",
  "CORS",
  "CSP",
  "XSS",
  "CSRF",
  "SQLi",
  "RCE"
];

const templates = [
  (term: string) => `The ${term} value appears in the architecture review.`,
  (term: string) => `Incident notes mention ${term} during mitigation.`,
  (term: string) => `A new runbook explains ${term} for onboarding.`,
  (term: string) => `The glossary entry for ${term} needs a canonical source.`
];

const corpus = terms.flatMap((term) =>
  templates.map((template) => ({
    sentence: template(term),
    expected: [term]
  }))
);

describe("detectAcronyms", () => {
  it("recovers at least 95% of acronyms in a 200-sentence labeled corpus", () => {
    const expectedCount = corpus.reduce((sum, item) => sum + item.expected.length, 0);
    const recoveredCount = corpus.reduce((sum, item) => {
      const detected = new Set(detectAcronyms(item.sentence));
      return sum + item.expected.filter((term) => detected.has(term)).length;
    }, 0);

    expect(corpus).toHaveLength(200);
    expect(recoveredCount / expectedCount).toBeGreaterThanOrEqual(0.95);
  });
});
