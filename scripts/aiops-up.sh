#!/usr/bin/env bash
# Build and deploy the storage anomaly detector (needs observability-up.sh first).
source "$(dirname "$0")/lib.sh"
log "Building and deploying the anomaly detector"
docker build -q -t ha-storage/aiops-detector:local "$REPO_ROOT/aiops"
k3d image import ha-storage/aiops-detector:local -c ha
kubectl apply -f "$REPO_ROOT/aiops/detector.yaml"
kubectl -n monitoring rollout status deployment/aiops-detector --timeout=180s
ok "detector running; it learns the baseline for ~4 minutes before judging"
