#!/usr/bin/env bash
# Deploy Garage (S3 backup target), initialise its layout, key and bucket, store the restic credentials
# in a Kubernetes Secret and install the nightly backup CronJob.
source "$(dirname "$0")/lib.sh"
B="$REPO_ROOT/backup"

log "Deploying Garage (S3-compatible backup store)"
kubectl create namespace backup --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n backup get secret garage-secrets >/dev/null 2>&1 \
  || kubectl -n backup create secret generic garage-secrets --from-literal=rpc-secret="$(openssl rand -hex 32)" >/dev/null
kubectl apply -f "$B/garage.yaml" >/dev/null
kubectl -n backup rollout status statefulset/garage --timeout=180s
G() { kubectl -n backup exec garage-0 -- /garage "$@"; }
retry 30 2 G status >/dev/null || fail "garage CLI not answering"

if G layout show 2>/dev/null | grep -q "No nodes currently have a role"; then
  log "Assigning the storage layout"
  node_id=$(G node id -q | cut -d@ -f1)
  G layout assign -z dc1 -c 4G "$node_id" >/dev/null
  G layout apply --version 1 >/dev/null
fi
G key info backup-key >/dev/null 2>&1 || G key create backup-key >/dev/null
G bucket info backups >/dev/null 2>&1 || G bucket create backups >/dev/null
G bucket allow --read --write --owner backups --key backup-key >/dev/null
info=$(G key info backup-key --show-secret)
key_id=$(awk -F': *' '/Key ID/ {print $2; exit}' <<<"$info" | tr -d ' ')
secret=$(awk -F': *' '/Secret key/ {print $2; exit}' <<<"$info" | tr -d ' ')
[ -n "$key_id" ] && [ -n "$secret" ] || { echo "$info"; fail "could not read the Garage key"; }
ok "Garage ready: bucket 'backups', key $key_id"

log "Storing restic credentials"
if kubectl -n ha get secret backup-restic >/dev/null 2>&1; then
  restic_pw=$(kubectl -n ha get secret backup-restic -o jsonpath='{.data.RESTIC_PASSWORD}' | base64 -d)
else
  restic_pw=$(openssl rand -hex 24)
fi
kubectl -n ha create secret generic backup-restic \
  --from-literal=RESTIC_REPOSITORY="s3:http://garage.backup:3900/backups" \
  --from-literal=RESTIC_PASSWORD="$restic_pw" \
  --from-literal=AWS_ACCESS_KEY_ID="$key_id" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$secret" \
  --from-literal=AWS_DEFAULT_REGION=garage \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl apply -f "$B/backup-cronjob.yaml" >/dev/null
ok "nightly backup CronJob installed (02:00): pg_dump + restic of the GlusterFS volume to Garage"
