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

# "Loaded event sources" is logged a few seconds BEFORE the kernel probes are attached: also wait for the
# pods to be Ready, and spawn a new shell on each attempt, so the test can't race Falco's startup.
kubectl -n falco wait pod -l app.kubernetes.io/name=falco --for=condition=Ready --timeout=180s >/dev/null \
  || { falco_logs | tail -40; fail "Falco pods not Ready"; }

log "Simulated intrusion: a shell is spawned inside an API pod"
pod=$(kubectl -n ha get pods -l app=api -o jsonpath='{.items[0].metadata.name}')
detected() { kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco --tail=-1 --since=5m 2>/dev/null | grep -q 'Shell in HA Storage container'; }
detect=""
for attempt in $(seq 1 12); do
  t0=$(date +%s)
  kubectl -n ha exec "$pod" -- sh -c 'id; ls /data | head -3' >/dev/null
  for _ in 1 2 3 4 5; do
    if detected; then detect=$(( $(date +%s) - t0 )); break 2; fi
    sleep 2
  done
  echo "  attempt $attempt: not detected yet (Falco may still be attaching its probes), spawning another shell"
done
[ -n "$detect" ] || { falco_logs | tail -60; fail "Falco did not detect the shell"; }
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
