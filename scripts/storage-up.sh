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
  || ansible-galaxy collection install community.docker >/dev/null

log "Configuring the cluster with Ansible"
cd "$REPO_ROOT/ansible"
# Pass the inventory and settings explicitly: Ansible ignores an ansible.cfg found in a world-writable
# directory (the Codespaces workspace is one), which silently left it with no hosts at all.
export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg" ANSIBLE_HOST_KEY_CHECKING=False        ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3 ANSIBLE_RETRY_FILES_ENABLED=False
play() { ansible-playbook -i "$REPO_ROOT/ansible/inventory.ini" "$REPO_ROOT/ansible/site.yml" "$@"; }
[ "$(ansible-inventory -i "$REPO_ROOT/ansible/inventory.ini" --list | jq '.gluster.hosts | length')" = "3" ]   || fail "Ansible inventory does not resolve the 3 GlusterFS nodes"
out=$(play) || { echo "$out"; fail "playbook failed"; }
echo "$out" | sed -n '/PLAY RECAP/,$p'
echo "$out" | grep -q "no hosts matched" && { echo "$out"; fail "a play matched no hosts"; }
ok "pool formed and volume '$VOLUME' started"

if [ "${1:-}" = "--check-idempotent" ]; then
  log "Idempotency check: second run must change nothing"
  out=$(play)
  echo "$out" | sed -n '/PLAY RECAP/,$p'
  if echo "$out" | sed -n '/PLAY RECAP/,$p' | grep -Eq 'changed=[1-9]'; then
    fail "playbook is not idempotent"
  fi
  ok "second run: changed=0 on every node"
fi

gl volume info "$VOLUME" | grep -E 'Type|Status|Number of Bricks|ping-timeout|quorum-type'
