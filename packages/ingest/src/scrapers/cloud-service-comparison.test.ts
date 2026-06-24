import { describe, expect, it } from "vitest";

import {
  comparisonRowsToRawEntries,
  htmlToComparisonRows,
  type ExistingCloudEntry
} from "./cloud-service-comparison.js";

const retrievedAt = "2026-06-24T00:00:00.000Z";

describe("cloud service comparison scraper", () => {
  it("parses the Google Cloud comparison table", () => {
    const rows = htmlToComparisonRows(tableFixture());

    expect(rows).toHaveLength(3);
    expect(rows[0]).toMatchObject({
      aws: [
        { name: "AWS CodeBuild", provider: "aws" },
        { name: "AWS CodeDeploy", provider: "aws" },
        { name: "AWS CodePipeline", provider: "aws" }
      ],
      azure: [
        { name: "Azure DevOps", provider: "azure" },
        { name: "GitHub Enterprise", provider: "azure" }
      ],
      category: "Serverless",
      gcp: [{ name: "Cloud Build", provider: "gcp", url: "https://cloud.google.com/build" }],
      serviceType: "CI/CD"
    });
    expect(rows[2]?.aws).toEqual([
      {
        name: "Amazon Elastic Compute Cloud (EC2) VM family (Trn1, Inf1, and P5)",
        provider: "aws",
        url: undefined
      }
    ]);
  });

  it("emits patch-shaped entries matched to existing cloud service terms", () => {
    const existing: ExistingCloudEntry[] = [
      {
        domains: ["aws", "cloud", "service names"],
        expansions: ["Amazon Elastic Compute Cloud"],
        meaning_short: "Amazon Elastic Compute Cloud",
        term: "EC2"
      },
      {
        domains: ["gcp", "google cloud", "service names"],
        expansions: ["Compute Engine API"],
        meaning_short: "Creates and runs virtual machines.",
        term: "compute"
      }
    ];
    const entries = comparisonRowsToRawEntries(
      htmlToComparisonRows(tableFixture()),
      retrievedAt,
      existing
    );

    const ec2 = entries.find((entry) => entry.term === "EC2");
    expect(ec2).toMatchObject({
      domains: [
        "aws",
        "cloud",
        "service names",
        "cloud service comparison",
        "compute",
        "core compute"
      ],
      expansion: "Amazon Elastic Compute Cloud",
      meaning: "Amazon Elastic Compute Cloud"
    });
    expect(ec2?.aliases).toEqual(
      expect.arrayContaining(["EC2", "Amazon Elastic Compute Cloud (EC2)"])
    );
    expect(ec2?.contemporaries).toEqual(
      expect.arrayContaining(["Compute Engine API", "Azure Virtual Machines"])
    );
    expect(entries.find((entry) => entry.term === "compute")).toMatchObject({
      contemporaries: ["Amazon Elastic Compute Cloud", "Azure Virtual Machines"],
      expansion: "Compute Engine API",
      meaning: "Creates and runs virtual machines."
    });
    expect(entries.find((entry) => entry.term === "AWS CodeBuild")).toMatchObject({
      contemporaries: [
        "Cloud Build",
        "AWS CodeDeploy",
        "AWS CodePipeline",
        "Azure DevOps",
        "GitHub Enterprise"
      ],
      sources: [
        {
          license: "CC-BY-4.0",
          publisher: "Google Cloud Documentation",
          source_quality: "canonical",
          url: "https://docs.cloud.google.com/docs/get-started/aws-azure-gcp-service-comparison"
        }
      ]
    });
  });

  it("aggregates duplicate service mappings into one entry", () => {
    const rows = htmlToComparisonRows(`
      <table><tbody>
        <tr><td>Data analytics</td><td>Messaging</td><td><a href="https://cloud.google.com/pubsub">Pub/Sub</a></td><td>Messaging.</td><td>Amazon MQ</td><td>Azure Service Bus Messaging</td></tr>
        <tr><td>Data analytics</td><td>Stream data ingest</td><td><a href="https://cloud.google.com/pubsub">Pub/Sub</a></td><td>Streaming.</td><td>Amazon Kinesis Data Streams</td><td>Azure Event Hubs</td></tr>
      </tbody></table>
    `);

    expect(
      comparisonRowsToRawEntries(rows, retrievedAt).find((entry) => entry.term === "Pub/Sub")
    ).toMatchObject({
      contemporaries: [
        "Amazon MQ",
        "Azure Service Bus Messaging",
        "Amazon Kinesis Data Streams",
        "Azure Event Hubs"
      ],
      expansion: "Pub/Sub"
    });
  });
});

function tableFixture(): string {
  return `
    <table>
      <thead>
        <tr>
          <th>Service category</th><th>Service type</th><th>Google Cloud product</th><th>Google Cloud product description</th><th>AWS offering</th><th>Azure offering</th>
        </tr>
      </thead>
      <tbody class="list">
        <tr>
          <td>Serverless</td>
          <td>CI/CD</td>
          <td><a href="https://cloud.google.com/build">Cloud Build</a></td>
          <td>Build, test, and deploy to Google Cloud runtime environments.</td>
          <td>AWS CodeBuild, AWS CodeDeploy, AWS CodePipeline</td>
          <td>Azure DevOps, GitHub Enterprise</td>
        </tr>
        <tr>
          <td>Compute</td>
          <td>Core compute</td>
          <td><a href="https://cloud.google.com/compute">Compute Engine</a></td>
          <td>Accelerate your digital transformation with high-performance VMs.</td>
          <td>Amazon Elastic Compute Cloud (EC2)</td>
          <td>Azure Virtual Machines</td>
        </tr>
        <tr>
          <td>Compute</td>
          <td>Core compute</td>
          <td><a href="https://cloud.google.com/tpu">Cloud TPU</a></td>
          <td>Train and run machine learning models faster than ever before.</td>
          <td>Amazon Elastic Compute Cloud (EC2) VM family (Trn1, Inf1, and P5)</td>
          <td>Azure ND VM family (H100, H200, MI300x, and others)</td>
        </tr>
      </tbody>
    </table>
  `;
}
