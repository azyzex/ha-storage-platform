#!/usr/bin/env bash
# Prove the monitoring works end to end: targets are scraped, killing a storage node fires an alert that
# reaches Alertmanager, and the alert resolves when the node comes back. Measures detection time.
source "$(dirname "$0")/lib.sh"
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
results=()
note() { results+=("| $1 | $2 |"); ok "$1: $2"; }

kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090 >/dev/null 2>&1 & PF1=$!
kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093 >/dev/null 2>&1 & PF2=$!
trap 'kill $PF1 $PF2 2>/dev/null || true' EXIT
retry 30 1 curl -fsS http://localhost:9090/-/ready >/dev/null || fail "Prometheus not ready"

q() { curl -fsG http://localhost:9090/api/v1/query --data-urlencode "query=$1" | jq -r '.data.result[0].value[1] // "0"'; }
firing() { q "count(ALERTS{alertname=\"$1\",alertstate=\"firing\"}) or vector(0)"; }
export -f q firing

log "1. Scrape targets"
retry 60 5 bash -c '[ "$(curl -fsG http://localhost:9090/api/v1/query --data-urlencode "query=sum(up{job=\"gluster\"})" | jq -r ".data.result[0].value[1] // 0")" = "3" ]' \
  || fail "gluster exporters not all scraped"
retry 60 5 bash -c '[ "$(curl -fsG http://localhost:9090/api/v1/query --data-urlencode "query=sum(up{job=\"api\"})" | jq -r ".data.result[0].value[1] // 0")" -ge 2 ]' \
  || fail "API pods not scraped"
note "Prometheus targets" "3/3 GlusterFS exporters + $(q 'sum(up{job="api"})') API pods up"
retry 30 5 bash -c '[ "$(curl -fsG http://localhost:9090/api/v1/query --data-urlencode "query=sum(storage_probe_seconds_count)" | jq -r ".data.result[0].value[1] // 0")" != "0" ]' \
  || fail "storage probe metrics missing"
# average over everything recorded so far (a short rate() window right after startup returns NaN)
avg=$(q 'sum(storage_probe_seconds_sum{op="write"}) / sum(storage_probe_seconds_count{op="write"})')
note "Storage probe" "average write+fsync $(awk -v v="$avg" 'BEGIN{printf "%.1f ms", v*1000}') through the FUSE mount"
[ "$(q 'count(min by (brick) (gluster_brick_up) == 1)')" = "3" ] || fail "bricks not all reported online"
note "Brick metrics" "3/3 bricks online"

log "2. Kill gluster-2 and wait for the alert"
docker stop gluster-2 >/dev/null
t0=$(date +%s)
retry 60 3 bash -c "[ \"\$(curl -fsG http://localhost:9090/api/v1/query --data-urlencode 'query=count(ALERTS{alertname=\"GlusterNodeDown\",alertstate=\"firing\"}) or vector(0)' | jq -r '.data.result[0].value[1]')\" != \"0\" ]" \
  || { docker start gluster-2 >/dev/null; fail "GlusterNodeDown never fired"; }
detect=$(( $(date +%s) - t0 ))
note "GlusterNodeDown" "fired ${detect}s after the node was stopped (rule: for 20s)"
retry 20 3 bash -c 'curl -fsS http://localhost:9093/api/v2/alerts | jq -e "any(.[]; .labels.alertname == \"GlusterNodeDown\")" >/dev/null' \
  || fail "alert did not reach Alertmanager"
note "Alertmanager" "received GlusterNodeDown (ready to route to email/Slack/Telegram)"
retry 30 3 bash -c '[ "$(firing GlusterBrickDown)" != "0" ]'   || fail "GlusterBrickDown did not fire: the surviving nodes still report gluster-2's brick online"
note "GlusterBrickDown" "firing too: the surviving nodes report gluster-2's brick offline"

log "3. Bring gluster-2 back and wait for the alert to resolve"
docker start gluster-2 >/dev/null
t0=$(date +%s)
retry 60 3 bash -c "[ \"\$(curl -fsG http://localhost:9090/api/v1/query --data-urlencode 'query=count(ALERTS{alertname=\"GlusterNodeDown\",alertstate=\"firing\"}) or vector(0)' | jq -r '.data.result[0].value[1]')\" = \"0\" ]" \
  || fail "alert did not resolve"
note "Recovery" "GlusterNodeDown resolved $(( $(date +%s) - t0 ))s after restart"
wait_healed || true

log "4. Logs: API access logs are searchable in Loki"
kubectl -n monitoring port-forward svc/loki 3100:3100 >/dev/null 2>&1 & PF3=$!
trap 'kill $PF1 $PF2 $PF3 2>/dev/null || true' EXIT
for _ in $(seq 1 10); do curl -fsS http://localhost:8080/api/files >/dev/null || true; done
logq='sum(count_over_time({namespace="ha", app="api"} |= "GET /api/files" [10m]))'
retry 40 3 bash -c "curl -fsG http://localhost:3100/loki/api/v1/query --data-urlencode 'query=$logq' | jq -e '(.data.result[0].value[1] // \"0\" | tonumber) > 0' >/dev/null" \
  || fail "no API logs in Loki"
lines=$(curl -fsG http://localhost:3100/loki/api/v1/query --data-urlencode "query=$logq" | jq -r '.data.result[0].value[1]')
note "Loki + Alloy" "$lines API access-log lines for GET /api/files found in Loki"

log "5. Grafana dashboard provisioned"
pw=$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)
retry 30 3 bash -c "curl -fsS -u admin:$pw 'http://localhost:8080/grafana/api/search?query=HA%20Storage' | jq -e 'length > 0' >/dev/null" \
  || fail "dashboard not provisioned"
note "Grafana" "dashboard 'HA Storage Platform' loaded, served at /grafana"

{
  echo "## Observability results"
  echo "| Check | Result |"
  echo "|---|---|"
  printf '%s\n' "${results[@]}"
} >> "$SUMMARY"
log "OBSERVABILITY PASSED"
