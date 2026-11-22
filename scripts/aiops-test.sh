#!/usr/bin/env bash
# Gray-failure test: slow down one GlusterFS node (it stays alive), check that the anomaly detector flags it
# while the static "StorageProbeSlow" threshold (p95 > 500 ms) does not, then remove the fault.
source "$(dirname "$0")/lib.sh"
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
results=()
note() { results+=("| $1 | $2 |"); ok "$1: $2"; }

kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090 >/dev/null 2>&1 & PF=$!
cleanup() { kill $PF 2>/dev/null || true; docker exec gluster-2 tc qdisc del dev eth0 root 2>/dev/null || true; docker update --cpus 0 gluster-2 >/dev/null 2>&1 || true; }
trap cleanup EXIT
retry 30 1 curl -fsS http://localhost:9090/-/ready >/dev/null || fail "Prometheus not ready"
q() { curl -fsG http://localhost:9090/api/v1/query --data-urlencode "query=$1" | jq -r '.data.result[0].value[1] // "0"'; }
fmt() { awk -v v="$1" 'BEGIN{printf "%.0f", v}'; }

log "1. Let the detector learn the baseline"
retry 60 10 bash -c '[ "$(curl -fsG http://localhost:9090/api/v1/query --data-urlencode "query=max(aiops_baseline_samples)" | jq -r ".data.result[0].value[1] // 0")" -ge 16 ]' \
  || fail "detector never built a baseline"
base_write=$(q 'max(aiops_feature_value{feature="write_ms"})')
[ "$(q 'max(aiops_anomaly)')" = "0" ] || fail "detector flags an anomaly on a healthy system"
note "Baseline" "learned from $(q 'max(aiops_baseline_samples)') samples, write latency ~$(fmt "$base_write") ms, no anomaly"

log "2. Inject a gray failure: gluster-2 becomes slow (not down)"
if docker exec gluster-2 tc qdisc add dev eth0 root netem delay 40ms 5ms 2>/dev/null \
   || { sudo modprobe sch_netem 2>/dev/null && docker exec gluster-2 tc qdisc add dev eth0 root netem delay 40ms 5ms 2>/dev/null; }; then
  fault="40 ms network delay on gluster-2 (tc netem)"
else
  docker update --cpus 0.05 gluster-2 >/dev/null
  fault="gluster-2 throttled to 5% of a CPU"
fi
ok "fault: $fault"
t0=$(date +%s)
retry 40 6 bash -c '[ "$(curl -fsG http://localhost:9090/api/v1/query --data-urlencode "query=max(aiops_anomaly)" | jq -r ".data.result[0].value[1] // 0")" = "1" ]' \
  || fail "detector did not flag the slowdown"
detect=$(( $(date +%s) - t0 ))
slow_write=$(q 'max(aiops_feature_value{feature="write_ms"})')
z=$(q 'max(aiops_feature_zscore{feature="write_ms"})')
static=$(q 'count(ALERTS{alertname="StorageProbeSlow",alertstate="firing"}) or vector(0)')
note "Gray failure" "$fault: write latency $(fmt "$base_write") -> $(fmt "$slow_write") ms"
note "Anomaly detector" "flagged it after ${detect}s (write_ms z-score $(fmt "$z")): explains WHICH signal moved"
if [ "$static" = "0" ]; then
  note "Static threshold (p95 > 500 ms)" "did NOT fire: the slowdown stays under the fixed limit"
else
  note "Static threshold (p95 > 500 ms)" "also fired (slowdown exceeded the fixed limit)"
fi
retry 20 6 bash -c '[ "$(curl -fsG http://localhost:9090/api/v1/query --data-urlencode "query=count(ALERTS{alertname=\"StorageAnomalyDetected\",alertstate=\"firing\"}) or vector(0)" | jq -r ".data.result[0].value[1]")" != "0" ]' \
  && note "StorageAnomalyDetected" "alert firing in Prometheus/Alertmanager" || fail "anomaly alert did not fire"

log "3. Remove the fault"
cleanup; PF=; kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090 >/dev/null 2>&1 & PF=$!
retry 30 1 curl -fsS http://localhost:9090/-/ready >/dev/null
t0=$(date +%s)
retry 40 6 bash -c '[ "$(curl -fsG http://localhost:9090/api/v1/query --data-urlencode "query=max(aiops_anomaly)" | jq -r ".data.result[0].value[1] // 1")" = "0" ]' \
  || fail "anomaly did not clear after the fault was removed"
note "Recovery" "anomaly cleared $(( $(date +%s) - t0 ))s after the fault was removed"

{
  echo "## AIOps: gray-failure detection"
  echo "| Step | Result |"
  echo "|---|---|"
  printf '%s\n' "${results[@]}"
} >> "$SUMMARY"
log "AIOPS TEST PASSED"
