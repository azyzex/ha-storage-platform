#!/usr/bin/env bash
# Load + chaos: k6 ramps to 40 users; the HPA must add API pods; halfway through, a GlusterFS node is
# killed and restarted. k6 thresholds (failures < 1%, p95 < 2 s) must still pass.
source "$(dirname "$0")/lib.sh"
K6_IMAGE=grafana/k6:1.8.3
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
WORK=$(mktemp -d)
chmod 777 "$WORK"   # k6 runs as a non-root user inside its container
results=()
note() { results+=("| $1 | $2 |"); ok "$1: $2"; }

kubectl apply -f "$REPO_ROOT/k8s/hpa.yaml" >/dev/null
retry 30 5 bash -c 'kubectl -n ha get hpa api -o jsonpath="{.status.currentMetrics[0].resource.current.averageUtilization}" | grep -q "[0-9]"' \
  || fail "HPA has no CPU metrics (metrics-server?)"
start_replicas=$(kubectl -n ha get deploy api -o jsonpath='{.spec.replicas}')

log "Starting k6 (40 users, 2.5 min) + watching the HPA"
max_replicas=$start_replicas
( while sleep 5; do kubectl -n ha get deploy api -o jsonpath='{.status.readyReplicas}' 2>/dev/null; echo; done ) > "$WORK/replicas.log" & WATCH=$!
( sleep 70; log "CHAOS: stopping gluster-3 under load"; docker stop gluster-3 >/dev/null; sleep 25; docker start gluster-3 >/dev/null ) & CHAOS=$!
set +e
docker run --rm --network host -v "$REPO_ROOT/loadtest:/scripts:ro" -v "$WORK:/out" "$K6_IMAGE" \
  run --quiet /scripts/storage-load.js
k6_rc=$?
set -e
wait $CHAOS || true
kill $WATCH 2>/dev/null || true
max_replicas=$(sort -n "$WORK/replicas.log" | tail -1)

[ -s "$WORK/summary.json" ] || fail "k6 produced no summary (rc=$k6_rc)"
reqs=$(jq -r '.metrics.http_reqs.values.count' "$WORK/summary.json")
rps=$(jq -r '.metrics.http_reqs.values.rate | floor' "$WORK/summary.json")
failed=$(jq -r '(.metrics.http_req_failed.values.rate * 10000 | floor) / 100' "$WORK/summary.json")
p95=$(jq -r '.metrics.http_req_duration.values["p(95)"] | floor' "$WORK/summary.json")
note "Load" "$reqs requests (~$rps req/s), $failed% failed, p95 ${p95} ms"
note "Chaos under load" "gluster-3 stopped for 25 s in the middle of the run"
note "Autoscaling (HPA)" "API pods $start_replicas -> $max_replicas"
[ "$k6_rc" = "0" ] || fail "k6 thresholds failed (rc=$k6_rc)"
[ "$max_replicas" -gt "$start_replicas" ] || fail "HPA did not scale up"
wait_healed || fail "self-heal did not finish after the chaos"
note "After the run" "self-heal complete, k6 thresholds passed"

{
  echo "## Load test + chaos"
  echo "| Check | Result |"
  echo "|---|---|"
  printf '%s\n' "${results[@]}"
} >> "$SUMMARY"
rm -rf "$WORK"
log "LOAD TEST PASSED"
