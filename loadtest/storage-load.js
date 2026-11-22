// k6 load test: users upload small files, list them and download them, ramping to 40 concurrent users.
// Thresholds make the run fail if more than 1% of requests fail or p95 latency exceeds 2 s.
import http from "k6/http";
import { check, sleep } from "k6";
import { randomBytes } from "k6/crypto";

const BASE = __ENV.BASE_URL || "http://localhost:8080";

export const options = {
  stages: [
    { duration: "30s", target: 15 },
    { duration: "90s", target: 40 },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<2000"],
    checks: ["rate>0.99"],
  },
  summaryTrendStats: ["avg", "med", "p(95)", "p(99)", "max"],
};

export default function () {
  const payload = http.file(randomBytes(64 * 1024), `load-${__VU}-${__ITER}.bin`, "application/octet-stream");
  const up = http.post(`${BASE}/api/files`, { file: payload }, { tags: { op: "upload" } });
  check(up, { "upload 201": (r) => r.status === 201 });

  const list = http.get(`${BASE}/api/files`, { tags: { op: "list" } });
  check(list, { "list 200": (r) => r.status === 200 });

  if (up.status === 201) {
    const id = up.json("id");
    const down = http.get(`${BASE}/api/files/${id}`, { tags: { op: "download" }, responseType: "binary" });
    check(down, { "download 200 + full size": (r) => r.status === 200 && r.body.byteLength === 64 * 1024 });
  }
  sleep(0.2);
}

// Machine-readable results for scripts/load-test.sh.
export function handleSummary(data) {
  const m = data.metrics;
  const line = `requests=${m.http_reqs.values.count} failed=${(m.http_req_failed.values.rate * 100).toFixed(2)}% ` +
    `p95=${m.http_req_duration.values["p(95)"].toFixed(0)}ms`;
  return { "/out/summary.json": JSON.stringify(data), stdout: `${line}
` };
}
