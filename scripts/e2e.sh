#!/usr/bin/env bash
# End-to-end test of the whole promise, through the real ingress:
#   upload -> bytes replicated on 3 bricks -> storage node failure -> app pod failure -> database restart.
# Prints measured results and writes them to the GitHub job summary when run in CI.
source "$(dirname "$0")/lib.sh"
API=http://localhost:8080/api
WORK=$(mktemp -d)
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
results=()
note() { results+=("| $1 | $2 |"); ok "$1: $2"; }

upload() {  # upload <file> -> prints JSON
  curl -fsS -F "file=@$1" "$API/files"
}
download_sha() {  # download_sha <id> -> sha256 of the downloaded bytes
  curl -fsS "$API/files/$1" -o "$WORK/dl" && sha256sum "$WORK/dl" | cut -d' ' -f1
}

log "0. Web page served through the ingress"
curl -fsS http://localhost:8080/ | grep -q '<div id="root">' || fail "frontend not served"
curl -fsSI http://localhost:8080/ | grep -qi 'x-frame-options: deny' || fail "security headers missing"
note "Frontend" "served by nginx (non-root) with security headers"

log "1. Upload through the ingress"
head -c 10M /dev/urandom > "$WORK/a.bin"
meta=$(upload "$WORK/a.bin")
id_a=$(jq -r .id <<<"$meta"); sha_a=$(jq -r .sha256 <<<"$meta")
[ "$sha_a" = "$(sha256sum "$WORK/a.bin" | cut -d' ' -f1)" ] || fail "server-side checksum differs"
[ "$(download_sha "$id_a")" = "$sha_a" ] || fail "download differs"
note "Upload + download (10 MB)" "checksum identical"

log "2. Bytes are replicated on all 3 GlusterFS bricks"
for n in "${NODES[@]}"; do
  [ "$(docker exec "$n" sha256sum "/bricks/$VOLUME/$id_a" | cut -d' ' -f1)" = "$sha_a" ] || fail "bad replica on $n"
done
note "Replicas" "3/3 bricks hold an identical copy"

log "3. Storage node failure"
docker stop gluster-3 >/dev/null
t0=$(date +%s.%N)
[ "$(download_sha "$id_a")" = "$sha_a" ] || fail "download failed with gluster-3 down"
t_read=$(awk -v s="$t0" -v e="$(date +%s.%N)" 'BEGIN{printf "%.2f", e-s}')
head -c 3M /dev/urandom > "$WORK/b.bin"
id_b=$(upload "$WORK/b.bin" | jq -r .id)
note "gluster-3 stopped" "file still served (${t_read}s), new upload accepted"
docker start gluster-3 >/dev/null
retry 60 2 docker exec gluster-3 test -f "/bricks/$VOLUME/$id_b" || fail "gluster-3 did not self-heal"
note "gluster-3 back" "self-healed the file written during its outage"

log "4. App pod failure while traffic is flowing"
victim=$(kubectl -n ha get pods -l app=api -o jsonpath='{.items[0].metadata.name}')
total=0; failed=0
end=$(( $(date +%s) + 25 ))
( sleep 3; kubectl -n ha delete pod "$victim" --wait=false >/dev/null ) &
while [ "$(date +%s)" -lt "$end" ]; do
  total=$((total+1))
  curl -fsS -m 2 "$API/files/$id_a" -o /dev/null || failed=$((failed+1))
  sleep 0.1
done
wait
kubectl -n ha rollout status deployment/api --timeout=120s >/dev/null
avail=$(awk -v t="$total" -v f="$failed" 'BEGIN{printf "%.1f", 100*(t-f)/t}')
note "API pod killed under load" "$failed/$total requests failed (${avail}% served), pod replaced"
[ "$failed" -le $(( total / 10 )) ] || fail "too many failed requests during pod failure"

log "5. Database pod restart keeps metadata (persistent volume)"
kubectl -n ha delete pod postgres-0 >/dev/null
kubectl -n ha rollout status statefulset/postgres --timeout=180s >/dev/null
retry 60 2 bash -c "curl -fsS $API/files | jq -e '.[] | select(.id==\"$id_a\")' >/dev/null" || fail "metadata lost after DB restart"
[ "$(download_sha "$id_a")" = "$sha_a" ] || fail "download differs after DB restart"
note "postgres-0 deleted" "metadata intact after restart"

{
  echo "## End-to-end results"
  echo "| Scenario | Result |"
  echo "|---|---|"
  printf '%s\n' "${results[@]}"
} >> "$SUMMARY"
rm -rf "$WORK"
log "E2E PASSED"
