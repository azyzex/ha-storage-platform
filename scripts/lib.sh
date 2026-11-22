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
wait_healed() {
  gl volume heal "$VOLUME" >/dev/null 2>&1 || true   # nudge the self-heal daemon
  retry 90 2 bash -c "out=\$(docker exec gluster-1 gluster --mode=script volume heal $VOLUME info); \
    [ \$(grep -c 'Number of entries: 0' <<<\"\$out\") -eq 3 ]"
}
