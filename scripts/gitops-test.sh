#!/usr/bin/env bash
# GitOps self-healing: change the live cluster by hand (as an operator or an attacker might) and measure how
# fast Argo CD puts it back to what Git says.
source "$(dirname "$0")/lib.sh"
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
results=()
note() { results+=("| $1 | $2 |"); ok "$1: $2"; }

log "1. A firewall rule is deleted by hand"
kubectl -n ha delete networkpolicy postgres-from-api-only >/dev/null
t0=$(date +%s)
retry 60 2 kubectl -n ha get networkpolicy postgres-from-api-only >/dev/null 2>&1 || fail "Argo CD did not restore the NetworkPolicy"
note "Deleted NetworkPolicy" "restored by Argo CD (selfHeal) in $(( $(date +%s) - t0 ))s"

log "2. Someone scales the frontend by hand"
kubectl -n ha scale deployment frontend --replicas=4 >/dev/null
t0=$(date +%s)
retry 60 2 bash -c '[ "$(kubectl -n ha get deploy frontend -o jsonpath={.spec.replicas})" = "2" ]' || fail "replicas not reverted"
note "Frontend scaled to 4 by hand" "reverted to 2 (the value in Git) in $(( $(date +%s) - t0 ))s"

log "3. A security setting is weakened by hand"
kubectl -n ha patch deployment frontend --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/securityContext/readOnlyRootFilesystem","value":false}]' >/dev/null
t0=$(date +%s)
retry 60 2 bash -c '[ "$(kubectl -n ha get deploy frontend -o jsonpath="{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}")" = "true" ]' \
  || fail "security setting not reverted"
note "readOnlyRootFilesystem disabled by hand" "re-enabled by Argo CD in $(( $(date +%s) - t0 ))s"

kubectl -n argocd get application ha-storage -o jsonpath='{.status.sync.status}/{.status.health.status}{"\n"}'
{
  echo "## GitOps (Argo CD) self-healing"
  echo "| Manual change | Result |"
  echo "|---|---|"
  printf '%s\n' "${results[@]}"
} >> "$SUMMARY"
log "GITOPS TEST PASSED"
