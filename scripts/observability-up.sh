#!/usr/bin/env bash
# Install Prometheus + Grafana + Alertmanager (kube-prometheus-stack), the alert rules, the API scrape config
# and the dashboard. Grafana is served at http://localhost:8080/grafana (user: admin).
source "$(dirname "$0")/lib.sh"
OBS="$REPO_ROOT/observability"

log "Installing kube-prometheus-stack"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -hex 12)" >/dev/null
fi
helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring \
  -f "$OBS/kps-values.yaml" --wait --timeout 12m
helm -n monitoring list -o json | jq -r '.[] | "chart: \(.chart)  app: \(.app_version)"'

log "Installing Loki (log store) + Grafana Alloy (log collector)"
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update grafana >/dev/null
helm upgrade --install loki grafana/loki -n monitoring -f "$OBS/loki-values.yaml" --wait --timeout 8m
helm upgrade --install alloy grafana/alloy -n monitoring -f "$OBS/alloy-values.yaml" --wait --timeout 5m
helm -n monitoring list -o json | jq -r '.[] | "\(.name): \(.chart)"'

log "Alert rules, API scraping, Grafana ingress and dashboard"
kubectl apply -f "$OBS/alerts.yaml" -f "$OBS/api-monitoring.yaml"
kubectl -n monitoring create configmap ha-storage-dashboard \
  --from-file=ha-storage.json="$OBS/dashboard.json" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n monitoring label configmap ha-storage-dashboard grafana_dashboard=1 --overwrite >/dev/null

log "Waiting for Grafana through the ingress"
retry 60 3 bash -c 'curl -fsS http://localhost:8080/grafana/api/health | jq -e ".database == \"ok\"" >/dev/null' \
  || fail "Grafana not reachable at /grafana"
ok "observability up — Grafana: http://localhost:8080/grafana  (password: kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
