#!/usr/bin/env bash
# Unmount and remove the storage cluster (add --purge to delete the bricks too).
source "$(dirname "$0")/lib.sh"
mountpoint -q "$MOUNT" && sudo umount "$MOUNT" || true
if [ "${1:-}" = "--purge" ]; then
  docker compose -f "$REPO_ROOT/storage/compose.yml" down -v
else
  docker compose -f "$REPO_ROOT/storage/compose.yml" down
fi
ok "storage down"
