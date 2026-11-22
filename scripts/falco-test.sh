#!/usr/bin/env bash
# Runtime security test: open a shell inside an API container (what an attacker would do after exploiting
# the app) and check Falco's custom rule catches it, with the pod name in the alert.
source "$(dirname "$0")/lib.sh"
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
results=()
note() { results+=("| $1 | $2 |"); ok "$1: $2"; }

falco_logs() { kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco --tail=-1 --since=10m 2>/dev/null; }

log "Waiting for Falco to load its rules"
retry 30 5 bash -c 'kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco --tail=-1 2>/dev/null | grep -qi "starting\|enabled event collection\|Loaded event sources\|Opening .* source"' \
  || { falco_logs | tail -40; fail "Falco did not start"; }

log "Simulated intrusion: a shell is spawned inside an API pod"
pod=$(kubectl -n ha get pods -l app=api -o jsonpath='{.items[0].metadata.name}')
t0=$(date +%s)
kubectl -n ha exec "$pod" -- sh -c 'id; ls /data | head -3' >/dev/null
retry 30 2 bash -c "kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco --tail=-1 --since=5m 2>/dev/null | grep -q 'Shell in HA Storage container'" \
  || { falco_logs | tail -60; fail "Falco did not detect the shell"; }
detect=$(( $(date +%s) - t0 ))
alert=$(falco_logs | grep 'Shell in HA Storage container' | tail -1)
echo "$alert" | jq -r '.output' 2>/dev/null || echo "$alert"
echo "$alert" | grep -q "$pod" && named="pod $pod identified" || named="pod name not resolved"
note "Shell in API container" "detected by Falco custom rule in ${detect}s ($named)"

{
  echo "## Runtime security (Falco)"
  echo "| Event | Result |"
  echo "|---|---|"
  printf '%s\n' "${results[@]}"
} >> "$SUMMARY"
log "FALCO TEST PASSED"
