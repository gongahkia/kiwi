import { describe, expect, it } from "vitest";

import { modelToRawEntry } from "./aws-services.js";

describe("aws services scraper", () => {
  it("maps service model metadata to service-name entries", () => {
    const entry = modelToRawEntry(
      "apis/ec2-2016-11-15.normal.json",
      {
        metadata: {
          endpointPrefix: "ec2",
          serviceFullName: "Amazon Elastic Compute Cloud",
          serviceId: "EC2"
        }
      },
      "2026-06-19T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      domains: ["aws", "cloud", "service names"],
      expansion: "Amazon Elastic Compute Cloud",
      meaning: "Amazon Elastic Compute Cloud",
      term: "EC2"
    });
    expect(entry?.sources[0]).toMatchObject({
      license: "Apache-2.0",
      publisher: "AWS SDK for JavaScript",
      source_quality: "canonical",
      url: "https://github.com/aws/aws-sdk-js/blob/master/apis/ec2-2016-11-15.normal.json"
    });
  });
});
