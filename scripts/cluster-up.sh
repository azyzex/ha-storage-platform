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

if ! k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
  log "Creating k3d cluster '$CLUSTER' (1 server + 2 agents)"
  k3d cluster create "$CLUSTER" \
    --agents 2 \
    --port "8080:80@loadbalancer" \
    --volume "$MOUNT:$MOUNT@all" \
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
retry 60 2 curl -fsS http://localhost:8080/api/readyz >/dev/null || {
  kubectl -n ha get pods -o wide; kubectl -n ha logs deploy/api --tail=50; fail "API not reachable"; }
kubectl -n ha get pods -o wide
ok "platform up: http://localhost:8080/api"
