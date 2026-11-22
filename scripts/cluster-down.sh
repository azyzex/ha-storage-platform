#!/usr/bin/env bash
# Delete the k3d cluster (the storage layer is left running; use storage-down.sh for that).
source "$(dirname "$0")/lib.sh"
k3d cluster delete ha || true
ok "cluster deleted"
