# One-command entry points. Run inside a Linux machine with Docker (e.g. the Codespace).
.PHONY: up storage platform observability backups aiops gitops falco test e2e drill load demo password argocd-password down purge

up: storage platform observability backups aiops gitops falco ## everything
	@echo; echo "Web app: http://localhost:8080   Grafana: http://localhost:8080/grafana (make password)"

storage:        ## 3 GlusterFS nodes (Ansible) + FUSE mount
	bash scripts/storage-up.sh && bash scripts/storage-mount.sh
platform:       ## k3d cluster + Postgres + API + frontend
	bash scripts/cluster-up.sh
observability:  ## Prometheus, Grafana, Alertmanager, Loki, Alloy
	bash scripts/observability-up.sh
backups:        ## Garage (S3) + nightly restic CronJob
	bash scripts/backup-up.sh
aiops:          ## anomaly detector
	bash scripts/aiops-up.sh
gitops:         ## Argo CD manages k8s/ from Git
	bash scripts/gitops-up.sh
falco:          ## Falco runtime security + custom rule
	bash scripts/falco-up.sh

test: e2e drill ## main automated checks
e2e:   ; bash scripts/e2e.sh
drill: ; bash scripts/restore-drill.sh
load:  ; bash scripts/load-test.sh

demo:           ## narrated step-by-step demo (pauses between steps, for recording)
	bash scripts/demo.sh

argocd-password: ## Argo CD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
password:       ## Grafana admin password
	@kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo

down:           ## delete the cluster and stop the storage nodes (data kept)
	bash scripts/cluster-down.sh; bash scripts/storage-down.sh
purge:          ## delete everything including data
	bash scripts/cluster-down.sh; bash scripts/storage-down.sh --purge
