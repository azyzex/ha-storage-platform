#!/usr/bin/env bash
# Install Falco (runtime security) with the platform's custom rule and Falcosidekick.
source "$(dirname "$0")/lib.sh"
log "Installing Falco"
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update falcosecurity >/dev/null
kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f - >/dev/null
helm upgrade --install falco falcosecurity/falco -n falco -f "$REPO_ROOT/security/falco-values.yaml" --wait --timeout 10m
helm -n falco list -o json | jq -r '.[] | "chart: \(.chart)  app: \(.app_version)"'
kubectl -n falco rollout status daemonset/falco --timeout=300s
ok "Falco running on every node"
