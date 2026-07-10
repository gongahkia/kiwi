import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const baseUrl = (__ENV.WAT_BENCHMARK_URL || "http://localhost:3000").replace(/\/$/, "");
const queries = JSON.parse(open("./packages/search/fixtures/dev-tooling-acronyms.json"));
const apiKey = __ENV.WAT_API_KEY || "";
const teamId = __ENV.WAT_TEAM_ID || "";
const userId = __ENV.WAT_USER_ID || "k6:search";
const context = __ENV.WAT_K6_CONTEXT || "";

export const searchFailures = new Rate("search_failures");
export const searchLatency = new Trend("search_latency_ms");

export const options = {
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: [`p(95)<${__ENV.WAT_K6_P95_MS || "200"}`],
    search_failures: ["rate<0.01"],
    search_latency_ms: [`p(95)<${__ENV.WAT_K6_P95_MS || "200"}`]
  },
  vus: Number(__ENV.WAT_K6_VUS || "10"),
  duration: __ENV.WAT_K6_DURATION || "1m"
};

export default function searchLoadTest() {
  const query = queries[(__VU + __ITER) % queries.length].query;
  const url = `${baseUrl}/api/v1/search?q=${encodeURIComponent(query)}&limit=5${
    context ? `&context=${encodeURIComponent(context)}` : ""
  }`;
  const headers = {};
  if (apiKey) headers.authorization = `Bearer ${apiKey}`;
  if (teamId) headers["x-wat-team-id"] = teamId;
  if (userId) headers["x-wat-user-id"] = userId;
  const response = http.get(url, {
    headers,
    tags: { route: "/api/v1/search" }
  });

  const ok = check(response, {
    "search returned 200": (res) => res.status === 200,
    "search returned matches": (res) => {
      const body = res.json();
      return Array.isArray(body.matches);
    }
  });

  searchFailures.add(!ok);
  searchLatency.add(response.timings.duration);
  sleep(Number(__ENV.WAT_K6_SLEEP_SECONDS || "0.1"));
}
