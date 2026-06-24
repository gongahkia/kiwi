import { describe, expect, it } from "vitest";

import {
  htmlToRawEntry,
  pgxnMetadataToRawEntry,
  readmeToRawEntry,
  type ExtensionSource
} from "./postgresql-extensions.js";

describe("postgresql extensions scraper", () => {
  it("maps PostgreSQL contrib extension docs", () => {
    const entry = htmlToRawEntry(
      {
        kind: "html",
        license: "PostgreSQL",
        name: "pg_trgm",
        parser: "postgres",
        publisher: "PostgreSQL Documentation",
        sourceQuality: "canonical",
        title: "PostgreSQL extension: pg_trgm",
        url: "https://www.postgresql.org/docs/current/pgtrgm.html"
      },
      `<html><body>
        <p>The <code class="filename">pg_trgm</code> module provides functions and operators for determining the similarity of alphanumeric text based on trigram matching.</p>
      </body></html>`,
      "2026-06-24T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      contemporaries: [],
      domains: ["postgresql", "database", "postgres extension"],
      expansion: "pg_trgm",
      meaning:
        "The pg_trgm module provides functions and operators for determining the similarity of alphanumeric text based on trigram matching.",
      term: "pg_trgm"
    });
    expect(entry?.sources[0]).toMatchObject({
      license: "PostgreSQL",
      publisher: "PostgreSQL Documentation",
      source_quality: "canonical",
      url: "https://www.postgresql.org/docs/current/pgtrgm.html"
    });
  });

  it("maps PGXN metadata for pgvector and pg_partman", () => {
    const vectorSource: Extract<ExtensionSource, { kind: "pgxn" }> = {
      aliases: ["vector"],
      expansion: "pgvector",
      kind: "pgxn",
      name: "pgvector",
      term: "pgvector",
      url: "https://api.pgxn.org/dist/vector.json"
    };
    const partmanSource: Extract<ExtensionSource, { kind: "pgxn" }> = {
      aliases: ["PostgreSQL Partition Manager"],
      expansion: "pg_partman",
      kind: "pgxn",
      name: "pg_partman",
      term: "pg_partman",
      url: "https://api.pgxn.org/dist/pg_partman.json"
    };

    expect(
      pgxnMetadataToRawEntry(
        vectorSource,
        {
          abstract: "Open-source vector similarity search for Postgres",
          license: { PostgreSQL: "http://www.postgresql.org/about/licence" },
          resources: { repository: { web: "https://github.com/pgvector/pgvector" } }
        },
        "2026-06-24T00:00:00.000Z"
      )
    ).toMatchObject({
      aliases: ["vector"],
      expansion: "pgvector",
      meaning: "Open-source vector similarity search for Postgres",
      sources: [{ license: "PostgreSQL", url: "https://github.com/pgvector/pgvector" }],
      term: "pgvector"
    });
    expect(
      pgxnMetadataToRawEntry(
        partmanSource,
        {
          abstract: "Extension to manage partitioned tables by time or ID",
          license: "postgresql",
          resources: { repository: { web: "https://github.com/pgpartman/pg_partman" } }
        },
        "2026-06-24T00:00:00.000Z"
      )
    ).toMatchObject({
      aliases: ["PostgreSQL Partition Manager"],
      expansion: "pg_partman",
      meaning: "Extension to manage partitioned tables by time or ID",
      sources: [{ license: "PostgreSQL", url: "https://github.com/pgpartman/pg_partman" }],
      term: "pg_partman"
    });
  });

  it("maps PostGIS docs as a standalone extension entry", () => {
    const entry = htmlToRawEntry(
      {
        kind: "html",
        license: "CC-BY-SA-3.0",
        name: "PostGIS",
        parser: "postgis",
        publisher: "PostGIS Project",
        sourceQuality: "canonical",
        title: "PostGIS extension: PostGIS",
        url: "https://postgis.net/docs/manual-dev/postgis_introduction.html"
      },
      `<html><body>
        <p>PostGIS is a spatial extension for the PostgreSQL relational database that was created by Refractions Research Inc.</p>
      </body></html>`,
      "2026-06-24T00:00:00.000Z"
    );

    expect(entry).toMatchObject({
      contemporaries: [],
      expansion: "PostGIS",
      meaning:
        "PostGIS is a spatial extension for the PostgreSQL relational database that was created by Refractions Research Inc.",
      sources: [{ license: "CC-BY-SA-3.0" }],
      term: "PostGIS"
    });
  });

  it("maps TimescaleDB and Citus README entries with contemporaries", () => {
    const timescale = readmeToRawEntry(
      {
        aliases: ["timescaledb"],
        contemporaries: ["Citus"],
        expansion: "TimescaleDB",
        kind: "readme",
        license: "Apache-2.0",
        name: "TimescaleDB",
        parser: "timescaledb",
        publisher: "TimescaleDB contributors",
        sourceQuality: "canonical",
        term: "TimescaleDB",
        title: "TimescaleDB README",
        url: "https://raw.githubusercontent.com/timescale/timescaledb/main/README.md"
      },
      "<h3>TimescaleDB is a PostgreSQL extension for high-performance real-time analytics on time-series and event data</h3>",
      "2026-06-24T00:00:00.000Z"
    );
    const citus = readmeToRawEntry(
      {
        aliases: ["citus"],
        contemporaries: ["TimescaleDB"],
        expansion: "Citus",
        kind: "readme",
        license: "AGPL-3.0-only",
        name: "Citus",
        parser: "citus",
        publisher: "Citus Data",
        sourceQuality: "canonical",
        term: "Citus",
        title: "Citus README",
        url: "https://raw.githubusercontent.com/citusdata/citus/main/README.md"
      },
      [
        "## What is Citus?",
        "",
        "Citus is a [PostgreSQL extension](https://example.com) that transforms Postgres into a distributed database.",
        "",
        "## Getting Started"
      ].join("\n"),
      "2026-06-24T00:00:00.000Z"
    );

    expect(timescale).toMatchObject({
      contemporaries: ["Citus"],
      meaning:
        "TimescaleDB is a PostgreSQL extension for high-performance real-time analytics on time-series and event data",
      sources: [{ license: "Apache-2.0" }],
      term: "TimescaleDB"
    });
    expect(citus).toMatchObject({
      contemporaries: ["TimescaleDB"],
      meaning:
        "Citus is a PostgreSQL extension that transforms Postgres into a distributed database.",
      sources: [{ license: "AGPL-3.0-only" }],
      term: "Citus"
    });
  });
});
