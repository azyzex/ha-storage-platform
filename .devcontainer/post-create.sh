#!/usr/bin/env bash
# One-time setup of the Codespace: GlusterFS client (same 11.x version as the server image), jq, acl, k3d,
# and Docker's data moved to the large scratch disk.
set -euo pipefail
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq glusterfs-client jq pipx acl >/dev/null
curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.8.3 bash
pipx ensurepath >/dev/null

# The workspace disk (32 GB) is ~60% full with the base image; the full stack needs more. Codespaces mount a
# large scratch disk on /tmp (~118 GB), so Docker's data goes there.
# Gotcha: /tmp carries a default ACL "default:other::rw-". Every directory created below it inherits
# "others may not enter", so every non-root process inside the k3s pods fails ("permission denied",
# "executable file not found"). Strip ACLs (-b) and default ACLs (-k) from Docker's directory first.
# Note: /tmp is wiped when the Codespace stops; after a restart, run `make up` again.
if [ "$(df --output=avail -BG /tmp | tail -1 | tr -dc 0-9)" -gt 40 ]; then
  DATA=/tmp/ha-docker
  sudo mkdir -p /etc/docker "$DATA"
  sudo setfacl -b -k "$DATA"
  sudo chmod 711 "$DATA"
  echo "{\"data-root\": \"$DATA\"}" | sudo tee /etc/docker/daemon.json >/dev/null
  sudo pkill dockerd || true
  for _ in $(seq 1 20); do pgrep dockerd >/dev/null || break; sleep 1; done
  sudo bash -c 'umask 022; nohup dockerd >/tmp/dockerd.log 2>&1 &'
  for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
  echo "Docker data root: $(docker info --format '{{.DockerRootDir}}')"
fi

echo
echo "Ready. Run:  make up    (then open the forwarded port 8080)"
