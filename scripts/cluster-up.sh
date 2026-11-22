#!/usr/bin/env bash
# Create the k3d (k3s) cluster on top of the mounted GlusterFS volume and deploy the app.
# Requires: storage-up.sh + storage-mount.sh done first (the mount must exist BEFORE the nodes start,
# so the bind mount into every node carries the GlusterFS filesystem).
source "$(dirname "$0")/lib.sh"
CLUSTER=ha
K3D_VERSION=v5.8.3

mountpoint -q "$MOUNT" || fail "$MOUNT is not mounted — run storage-up.sh and storage-mount.sh first"

if ! command -v k3d >/dev/null; then
  log "Installing k3d $K3D_VERSION"
  curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=$K3D_VERSION bash
fi
command -v kubectl >/dev/null || fail "kubectl not installed"

# k3s stacks containerd's overlayfs snapshotter on the node's own root filesystem. Where that root is
# itself an overlay that can't host an overlay upper dir (Codespaces: Docker 29 + containerd image store),
# containers silently start with an empty filesystem ("executable file not found"). The "native"
# snapshotter copies layers instead: slower, more disk, works everywhere. Override with K3S_SNAPSHOTTER.
SNAPSHOTTER=${K3S_SNAPSHOTTER:-$([ "${CODESPACES:-}" = "true" ] && echo native || echo overlayfs)}

if ! k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
  log "Creating k3d cluster '$CLUSTER' (1 server + 2 agents, snapshotter: $SNAPSHOTTER)"
  # The 3 k3d nodes share ONE host disk. Default kubelet eviction (nodefs/imagefs < 10-15% free) evicts pods
  # on a busy single machine (CI runner, Codespace) long before space really runs out, so set explicit,
  # lab-appropriate thresholds.
  k3d cluster create "$CLUSTER" \
    --agents 2 \
    --port "8080:80@loadbalancer" \
    --volume "$MOUNT:$MOUNT@all" \
    --k3s-arg "--kubelet-arg=eviction-hard=memory.available<200Mi,nodefs.available<3%,imagefs.available<3%@server:*;agent:*" \
    --k3s-arg "--kubelet-arg=eviction-minimum-reclaim=nodefs.available=500Mi,imagefs.available=500Mi@server:*;agent:*" \
    --k3s-arg "--snapshotter=$SNAPSHOTTER@server:*;agent:*" \
    --wait --timeout 180s
fi
kubectl config use-context "k3d-$CLUSTER" >/dev/null
kubectl get nodes -o wide

log "Checking every node sees the GlusterFS volume"
for node in $(k3d node list -o json | jq -r '.[] | select(.role=="server" or .role=="agent") | .name'); do
  docker exec "$node" sh -c "touch $MOUNT/.node-check-$node && ls $MOUNT/.node-check-$node && rm $MOUNT/.node-check-$node" >/dev/null \
    || fail "node $node cannot write to $MOUNT"
done
ok "all nodes share the GlusterFS volume"

log "Building and importing the images"
docker build -q -t ha-storage/api:local "$REPO_ROOT/app/api"
docker build -q -t ha-storage/frontend:local "$REPO_ROOT/app/frontend"
k3d image import ha-storage/api:local ha-storage/frontend:local -c "$CLUSTER"

log "Deploying"
kubectl apply -f "$REPO_ROOT/k8s/namespace.yaml"
if ! kubectl -n ha get secret postgres-credentials >/dev/null 2>&1; then
  kubectl -n ha create secret generic postgres-credentials --from-literal=password="$(openssl rand -hex 24)"
fi
kubectl apply -k "$REPO_ROOT/k8s"
kubectl -n ha rollout status statefulset/postgres --timeout=180s
kubectl -n ha rollout status deployment/api --timeout=180s
kubectl -n ha rollout status deployment/frontend --timeout=180s

log "Waiting for the API through the ingress"
# Check the body, not just "200 OK": a misrouted request can get the frontend's index.html with a 200.
api_ok() { curl -fsS http://localhost:8080/api/readyz | jq -e '.status == "ready"' >/dev/null 2>&1; }
retry 60 2 api_ok || {
  echo "--- response for /api/readyz:"; curl -si http://localhost:8080/api/readyz | head -15
  kubectl get ingress -A -o yaml; kubectl -n kube-system logs deploy/traefik --tail=60
  kubectl -n ha get pods -o wide; kubectl -n ha logs deploy/api --tail=50; fail "API not reachable through the ingress"; }
kubectl -n ha get pods -o wide
ok "platform up: http://localhost:8080/api"
