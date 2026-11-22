#!/usr/bin/env bash
# Install Argo CD and hand the platform's k8s/ folder over to it (GitOps).
# Repo access: GITHUB_TOKEN (CI / Codespaces) or the gh CLI token. Revision: GITHUB_SHA in CI, else main.
source "$(dirname "$0")/lib.sh"
REPO_URL=${REPO_URL:-https://github.com/azyzex/ha-storage-platform.git}
REVISION=${GITHUB_SHA:-main}
TOKEN=${GITHUB_TOKEN:-}
# Codespaces keep the repo token in a shared env file that the VS Code terminal loads but SSH sessions don't.
CS_ENV=/workspaces/.codespaces/shared/.env
[ -z "$TOKEN" ] && [ -r "$CS_ENV" ] && TOKEN=$(sed -n 's/^GITHUB_TOKEN=//p' "$CS_ENV" | tr -d '"' | head -1)
[ -z "$TOKEN" ] && TOKEN=$(gh auth token 2>/dev/null || true)

log "Installing Argo CD"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
helm upgrade --install argocd argo/argo-cd -n argocd -f "$REPO_ROOT/gitops/argocd-values.yaml" --wait --timeout 10m
helm -n argocd list -o json | jq -r '.[] | "chart: \(.chart)  app: \(.app_version)"'

if [ -n "$TOKEN" ]; then
  log "Registering the (private) Git repository"
  kubectl -n argocd create secret generic repo-ha-storage \
    --from-literal=type=git --from-literal=url="$REPO_URL" \
    --from-literal=username=x-access-token --from-literal=password="$TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n argocd label secret repo-ha-storage argocd.argoproj.io/secret-type=repository --overwrite >/dev/null
fi

log "Creating the Application (source: $REPO_URL @ $REVISION, path k8s/)"
sed -e "s#__REPO__#$REPO_URL#" -e "s#__REVISION__#$REVISION#" "$REPO_ROOT/gitops/application.yaml" | kubectl apply -f -
# force an immediate re-read of the repo (picks up credentials added after a failed first attempt)
kubectl -n argocd annotate application ha-storage argocd.argoproj.io/refresh=hard --overwrite >/dev/null
retry 60 5 bash -c '[ "$(kubectl -n argocd get application ha-storage -o jsonpath="{.status.sync.status}/{.status.health.status}")" = "Synced/Healthy" ]' \
  || { kubectl -n argocd get application ha-storage -o yaml | sed -n '/status:/,$p' | head -60; fail "application not Synced/Healthy"; }
ok "Argo CD manages the platform: Synced/Healthy — UI at http://localhost:8080/argocd (admin / make argocd-password)"
