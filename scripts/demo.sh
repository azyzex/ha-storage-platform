#!/usr/bin/env bash
# Narrated demo for recording. Each step explains what is about to happen, waits for Enter, then does it.
# Keep Grafana open next to the terminal (http://localhost:8080/grafana, dashboard "HA Storage Platform").
source "$(dirname "$0")/lib.sh"
API=http://localhost:8080/api
step() { printf '\n\033[1;33m▶ %s\033[0m\n' "$1"; read -r -p "  (Enter to run) " _; }
WORK=$(mktemp -d)

step "1. Upload a 20 MB file through the web entry point (Traefik → FastAPI on Kubernetes)"
head -c 20M /dev/urandom > "$WORK/demo.bin"
sha=$(sha256sum "$WORK/demo.bin" | cut -d' ' -f1)
meta=$(curl -fsS -F "file=@$WORK/demo.bin" "$API/files"); echo "$meta" | jq .
id=$(jq -r .id <<<"$meta")

step "2. The same bytes are on all 3 GlusterFS bricks (replica 3)"
for n in "${NODES[@]}"; do printf '  %-10s ' "$n"; docker exec "$n" sha256sum "/bricks/$VOLUME/$id" | cut -c1-16; done
echo "  original   ${sha:0:16}"

step "3. Kill storage node gluster-2 — watch the Grafana panels turn red and the alert fire (~40 s)"
docker stop gluster-2 >/dev/null; echo "  gluster-2 stopped"

step "4. Download the file anyway: still served, identical checksum"
time (curl -fsS "$API/files/$id" -o "$WORK/back.bin")
[ "$(sha256sum "$WORK/back.bin" | cut -d' ' -f1)" = "$sha" ] && echo "  ✔ identical"

step "5. Kill an API pod — Kubernetes replaces it; the other pod keeps serving"
kubectl -n ha delete pod "$(kubectl -n ha get pods -l app=api -o jsonpath='{.items[0].metadata.name}')" --wait=false
sleep 2; kubectl -n ha get pods -l app=api

step "6. Bring gluster-2 back — self-heal copies what it missed, the alert resolves"
docker start gluster-2 >/dev/null; wait_healed && echo "  ✔ healed"
docker exec gluster-1 gluster --mode=script volume heal "$VOLUME" info | grep -E 'Brick|entries'

step "7. Accidental delete: replication can't help (the delete is replicated) — the backup can"
curl -fsS -X DELETE "$API/files/$id" && echo "  deleted; GET now returns $(curl -s -o /dev/null -w '%{http_code}' "$API/files/$id")"
echo "  (run 'make drill' to see the full backup → delete → restore cycle)"

rm -rf "$WORK"
printf '\n\033[1;32mDemo done.\033[0m\n'
