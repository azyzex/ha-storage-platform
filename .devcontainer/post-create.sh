#!/usr/bin/env bash
# One-time setup of the Codespace: GlusterFS client (same 11.x version as the server image), jq, k3d.
set -euo pipefail
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq glusterfs-client jq pipx >/dev/null
curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.8.3 bash
pipx ensurepath >/dev/null
echo
echo "Ready. Run:  make up    (then open the forwarded port 8080)"
