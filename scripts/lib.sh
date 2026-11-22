# Shared helpers for the scripts.
set -euo pipefail
log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }
# retry <tries> <sleep> <cmd...>
retry() { local n=$1 s=$2; shift 2; for ((i=1;i<=n;i++)); do "$@" && return 0; sleep "$s"; done; return 1; }
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VOLUME=files
MOUNT=/mnt/gluster
NODES=(gluster-1 gluster-2 gluster-3)
declare -A NODE_IP=( [gluster-1]=172.28.0.11 [gluster-2]=172.28.0.12 [gluster-3]=172.28.0.13 )
gl() { docker exec gluster-1 gluster --mode=script "$@"; }
# Wait until self-heal has nothing pending on any brick (a file can exist on the returning
# brick before its data is fully copied, so "file exists" is not "healed").
# Uses "statistics heal-count" (reads the heal index counters) instead of "heal info", which walks every
# pending entry and becomes very slow after thousands of writes during an outage.
heal_pending_zero() {
  local out
  out=$(timeout 30 docker exec gluster-1 gluster --mode=script volume heal "$VOLUME" statistics heal-count 2>/dev/null) || return 1
  [ "$(grep -c 'Number of entries: 0' <<<"$out")" -eq 3 ]
}
wait_healed() {
  timeout 30 docker exec gluster-1 gluster --mode=script volume heal "$VOLUME" >/dev/null 2>&1 || true  # nudge
  retry 120 3 heal_pending_zero
}
