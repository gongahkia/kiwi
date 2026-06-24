import { describe, expect, it } from "vitest";

import { yamlToRawEntries } from "./cncf-landscape.js";

const retrievedAt = "2026-06-24T00:00:00.000Z";

describe("cncf landscape scraper", () => {
  it("maps landscape items to system entries with category contemporaries", () => {
    const entries = yamlToRawEntries(
      [
        "landscape:",
        "  - category:",
        "    name: Orchestration & Management",
        "    subcategories:",
        "      - subcategory:",
        "        name: Service Mesh",
        "        items:",
        "          - item:",
        "            name: Istio",
        "            description: Connect, secure, control, and observe services.",
        "            homepage_url: https://istio.io/",
        "            repo_url: https://github.com/istio/istio",
        "            project: graduated",
        "            extra:",
        "              tag: network",
        "          - item:",
        "            name: Linkerd",
        "            description: Ultralight service mesh.",
        "            homepage_url: https://linkerd.io/",
        "            repo_url: https://github.com/linkerd/linkerd2",
        "            project: graduated",
        "          - item:",
        "            name: Envoy",
        "            description: Cloud-native high-performance edge/middle/service proxy.",
        "            homepage_url: https://www.envoyproxy.io/",
        "            repo_url: https://github.com/envoyproxy/envoy",
        "            project: graduated",
        "      - subcategory:",
        "        name: Scheduling & Orchestration",
        "        items:",
        "          - item:",
        "            name: Kubernetes",
        "            description: Production-grade container orchestration.",
        "            homepage_url: https://kubernetes.io/",
        "            repo_url: https://github.com/kubernetes/kubernetes",
        "            project: graduated"
      ].join("\n"),
      retrievedAt
    );

    expect(entries).toHaveLength(4);
    expect(entries.find((entry) => entry.term === "Istio")).toMatchObject({
      contemporaries: ["Linkerd", "Envoy"],
      domains: [
        "cncf",
        "cloud native",
        "cncf landscape",
        "system",
        "orchestration & management",
        "service mesh",
        "cncf:graduated",
        "tag:network"
      ],
      expansion: "Istio",
      meaning: "Connect, secure, control, and observe services."
    });
    expect(entries.find((entry) => entry.term === "Kubernetes")?.contemporaries).toEqual([]);
    expect(entries.find((entry) => entry.term === "Istio")?.sources[0]).toMatchObject({
      license: "Apache-2.0",
      publisher: "CNCF Landscape",
      retrieved_at: retrievedAt,
      source_quality: "canonical",
      url: "https://github.com/cncf/landscape/blob/master/landscape.yml"
    });
  });

  it("uses secondary paths and derives conservative aliases", () => {
    const entries = yamlToRawEntries(
      [
        "landscape:",
        "  - category:",
        "    name: Runtime",
        "    subcategories:",
        "      - subcategory:",
        "        name: Container Runtime",
        "        items:",
        "          - item:",
        "            name: containerd",
        "            second_path:",
        "              - Orchestration & Management / Scheduling & Orchestration",
        "          - item:",
        "            name: Apache Mesos",
        "            description: Cluster manager.",
        "            second_path:",
        "              - Orchestration & Management / Scheduling & Orchestration",
        "  - category:",
        "    name: Provisioning",
        "    subcategories:",
        "      - subcategory:",
        "        name: Automation & Configuration",
        "        items:",
        "          - item:",
        "            name: CDK for Kubernetes (CDK8s)",
        "            description: Define Kubernetes apps using familiar programming languages."
      ].join("\n"),
      retrievedAt
    );

    expect(entries.find((entry) => entry.term === "containerd")).toMatchObject({
      contemporaries: ["Apache Mesos"],
      meaning: "containerd is listed in the CNCF Landscape under Runtime / Container Runtime."
    });
    expect(entries.find((entry) => entry.term === "Apache Mesos")?.aliases).toEqual(["Mesos"]);
    expect(entries.find((entry) => entry.term === "CDK for Kubernetes (CDK8s)")?.aliases).toEqual([
      "CDK8s"
    ]);
  });
});
