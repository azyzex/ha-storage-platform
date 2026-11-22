#!/usr/bin/env bash
# Prove the core promise: files survive losing a node, and the node catches up when it returns.
source "$(dirname "$0")/lib.sh"

f1="$MOUNT/smoke-before-failure.bin"
f2="$MOUNT/smoke-during-failure.bin"

log "1. Write a 20 MB file while all 3 nodes are up"
head -c 20M /dev/urandom > "$f1"
sum1=$(sha256sum "$f1" | cut -d' ' -f1)
for n in "${NODES[@]}"; do
  docker exec "$n" test -f "/bricks/$VOLUME/$(basename "$f1")" || fail "replica missing on $n"
done
ok "file replicated on all 3 bricks (sha256 ${sum1:0:12}...)"

log "2. Stop gluster-2 (simulated node failure)"
docker stop gluster-2 >/dev/null
start=$(date +%s.%N)
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
got=$(sha256sum "$f1" | cut -d' ' -f1)
elapsed=$(awk -v s="$start" -v e="$(date +%s.%N)" 'BEGIN{printf "%.2f", e-s}')
[ "$got" = "$sum1" ] || fail "checksum mismatch after node failure"
ok "file still readable with gluster-2 down, checksum identical (read took ${elapsed}s)"

log "3. Write a new file while gluster-2 is still down"
head -c 5M /dev/urandom > "$f2"
sum2=$(sha256sum "$f2" | cut -d' ' -f1)
ok "write accepted with 2 of 3 nodes"

log "4. Bring gluster-2 back and wait for self-heal"
docker start gluster-2 >/dev/null
retry 60 2 docker exec gluster-2 test -f "/bricks/$VOLUME/$(basename "$f2")" || {
  gl volume heal "$VOLUME" info; fail "gluster-2 did not heal the file written during its outage"; }
got2=$(docker exec gluster-2 sha256sum "/bricks/$VOLUME/$(basename "$f2")" | cut -d' ' -f1)
[ "$got2" = "$sum2" ] || fail "healed copy on gluster-2 differs"
ok "gluster-2 healed: missing file copied back, checksum identical"

retry 30 2 bash -c "docker exec gluster-1 gluster --mode=script volume heal $VOLUME info | grep -q 'Number of entries: 0'" || true
gl volume heal "$VOLUME" info | grep -E 'Brick|Number of entries'

log "Storage smoke test PASSED"
