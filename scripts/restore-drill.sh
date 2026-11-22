#!/usr/bin/env bash
# Disaster-recovery drill: the failure replication cannot fix.
#   back up -> delete a file through the API (the delete reaches all 3 replicas instantly) -> restore from
#   backup -> the file is back with the same checksum. Measures the restore time.
source "$(dirname "$0")/lib.sh"
API=http://localhost:8080/api
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
WORK=$(mktemp -d)
results=()
note() { results+=("| $1 | $2 |"); ok "$1: $2"; }
run_job() {  # run_job <name>: wait for completion, print logs, fail on error
  if ! kubectl -n ha wait --for=condition=complete "job/$1" --timeout=300s >/dev/null; then
    kubectl -n ha describe job "$1" | tail -20
    kubectl -n ha logs "job/$1" --all-containers --tail=50 || true
    fail "job $1 failed"
  fi
  kubectl -n ha logs "job/$1" --all-containers --tail=8
}

log "1. An important file"
head -c 2M /dev/urandom > "$WORK/contract.pdf"
sha=$(sha256sum "$WORK/contract.pdf" | cut -d' ' -f1)
id=$(curl -fsS -F "file=@$WORK/contract.pdf" "$API/files" | jq -r .id)
ok "uploaded $id"

log "2. Backup (same job as the nightly CronJob)"
job="backup-drill-$(date +%s)"
kubectl -n ha create job "$job" --from=cronjob/backup >/dev/null
t0=$(date +%s); run_job "$job"
note "Backup" "pg_dump + restic snapshot to Garage (S3) in $(( $(date +%s) - t0 ))s"

log "3. Disaster: the file is deleted"
curl -fsS -X DELETE "$API/files/$id" >/dev/null
[ "$(curl -s -o /dev/null -w '%{http_code}' "$API/files/$id")" = "404" ] || fail "file still served after delete"
for n in "${NODES[@]}"; do docker exec "$n" test ! -e "/bricks/$VOLUME/$id" || fail "replica still on $n"; done
note "Accidental delete" "gone from all 3 replicas: replication alone cannot bring it back"

log "4. Restore from the latest snapshot"
job="restore-drill-$(date +%s)"
sed "s/__NAME__/$job/" "$REPO_ROOT/backup/restore-job.yaml" | kubectl apply -f - >/dev/null
t0=$(date +%s); run_job "$job"
rto=$(( $(date +%s) - t0 ))

log "5. Verify"
curl -fsS "$API/files/$id" -o "$WORK/back.pdf" || fail "file not served after restore"
[ "$(sha256sum "$WORK/back.pdf" | cut -d' ' -f1)" = "$sha" ] || fail "restored file differs"
curl -fsS "$API/files" | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null || fail "metadata not restored"
note "Restore" "file + metadata back, checksum identical, restore took ${rto}s"

{
  echo "## Backup / disaster-recovery drill"
  echo "| Step | Result |"
  echo "|---|---|"
  printf '%s\n' "${results[@]}"
} >> "$SUMMARY"
rm -rf "$WORK"
log "RESTORE DRILL PASSED"
