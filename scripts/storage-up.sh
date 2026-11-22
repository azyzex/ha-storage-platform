#!/usr/bin/env bash
# Build and start the 3 GlusterFS nodes, form the trusted pool, create + start a replica-3 volume.
source "$(dirname "$0")/lib.sh"

log "Starting GlusterFS nodes"
docker compose -f "$REPO_ROOT/storage/compose.yml" up -d --build

log "Waiting for glusterd on every node"
for n in "${NODES[@]}"; do
  retry 30 2 docker exec "$n" gluster --mode=script pool list >/dev/null || fail "glusterd not ready on $n"
done
ok "glusterd running on ${NODES[*]}"

log "Forming the trusted storage pool"
for n in gluster-2 gluster-3; do gl peer probe "$n" >/dev/null || true; done
retry 30 2 bash -c '[ "$(docker exec gluster-1 gluster --mode=script pool list | grep -c Connected)" -eq 3 ]' \
  || { gl pool list; fail "peers not connected"; }
gl pool list
ok "3 peers connected"

if ! gl volume info "$VOLUME" >/dev/null 2>&1; then
  log "Creating replica-3 volume '$VOLUME'"
  # 'force' because bricks sit on the container root volume (fine for a lab, documented in docs/PLAN.md).
  gl volume create "$VOLUME" replica 3 \
     gluster-1:/bricks/$VOLUME gluster-2:/bricks/$VOLUME gluster-3:/bricks/$VOLUME force
  # Detect a dead node in 5 s instead of the default 42 s (keeps the failover demo short).
  gl volume set "$VOLUME" network.ping-timeout 5
  gl volume start "$VOLUME"
fi
gl volume info "$VOLUME"
ok "volume '$VOLUME' started"
