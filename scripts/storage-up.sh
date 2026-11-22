#!/usr/bin/env bash
# Start the 3 GlusterFS node containers, then let Ansible build the trusted pool and the replica-3 volume.
# Usage: storage-up.sh [--check-idempotent]   (second flag re-runs the playbook and fails if anything changes)
source "$(dirname "$0")/lib.sh"

log "Starting GlusterFS nodes"
docker compose -f "$REPO_ROOT/storage/compose.yml" up -d --build

if ! command -v ansible-playbook >/dev/null; then
  log "Installing ansible-core + community.docker"
  pipx install --quiet "ansible-core>=2.17,<2.19" >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
fi
ansible-galaxy collection list community.docker >/dev/null 2>&1 \
  || ansible-galaxy collection install -q community.docker

log "Configuring the cluster with Ansible"
cd "$REPO_ROOT/ansible"
ansible-playbook site.yml
ok "pool formed and volume '$VOLUME' started"

if [ "${1:-}" = "--check-idempotent" ]; then
  log "Idempotency check: second run must change nothing"
  out=$(ansible-playbook site.yml)
  echo "$out" | sed -n '/PLAY RECAP/,$p'
  if echo "$out" | sed -n '/PLAY RECAP/,$p' | grep -Eq 'changed=[1-9]'; then
    fail "playbook is not idempotent"
  fi
  ok "second run: changed=0 on every node"
fi

gl volume info "$VOLUME" | grep -E 'Type|Status|Number of Bricks|ping-timeout|quorum-type'
