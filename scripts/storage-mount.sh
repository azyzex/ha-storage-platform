#!/usr/bin/env bash
# Mount the Gluster volume on the host with the native FUSE client.
source "$(dirname "$0")/lib.sh"

log "Installing GlusterFS client (if missing)"
command -v mount.glusterfs >/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq glusterfs-client; }

log "Making node names resolvable on the host"
for n in "${NODES[@]}"; do
  grep -q " $n\$" /etc/hosts || echo "${NODE_IP[$n]} $n" | sudo tee -a /etc/hosts >/dev/null
done

log "Mounting $VOLUME at $MOUNT"
sudo mkdir -p "$MOUNT"
mountpoint -q "$MOUNT" || sudo mount -t glusterfs -o backup-volfile-servers=gluster-2:gluster-3 "gluster-1:/$VOLUME" "$MOUNT"
sudo chmod 1777 "$MOUNT"
mountpoint "$MOUNT"
df -h "$MOUNT"
ok "mounted"
