# HA Storage Platform: Build Plan

> **What this file is:** the full plan for Aziz's flagship PFE portfolio project. It is the single source of truth: if the chat is lost, start from here and from `docs/STATUS.md`.
> **Owner:** Mohamed Aziz Guenni · **Started:** 2026-11-22 · **Target:** core working before 30 Nov 2026, remaining layers right after.

---

## 1. The project in plain words

A small **file-storage service that does not lose files and does not go down**.

- People upload and download files through a web page.
- Every file is **copied onto 3 storage nodes** (GlusterFS). Kill one node and the file is still there and still downloads.
- The application runs on **Kubernetes**, which restarts anything that crashes and adds copies of the app when traffic grows.
- Everything is **watched** (metrics, logs, dashboards, alarms), a small **AI model** flags unusual storage behaviour early, every change goes through a **security-checked pipeline**, and the data is **backed up** somewhere separate.
- It runs in the **cloud** (GitHub Codespaces for the live demo, GitHub Actions for automated tests).

**The 30-second demo:** upload a file, stop one storage node, download the file again: still there, same checksum. Kill an app pod: Kubernetes brings it back. Flood the app with traffic: Kubernetes adds pods.

**What kind of ops this is:** DevOps / SRE (platform and reliability) with an AIOps layer (observability + anomaly detection) and a DevSecOps layer (security in the pipeline). These are the 3 most-requested ops profiles in the 2027 Tunisian PFE market (see `PFE SUBMITTION/00_MASTER/ops-demand-tunisia.md`).

---

## 2. Architecture

```text
                         Users (browser)
                               |
                     Traefik ingress (k3s)
                     /                    \
            frontend (React+nginx)     api (FastAPI)  <--- HPA: 2..6 pods
                                         |      \
                              PostgreSQL       /data (hostPath)
                            (metadata only)       |
                            local-path PVC        |  bind mount into every k3d node
                                                  |
   ------------------------- host (Codespace / CI runner) ------------------------
                                                  |
                                    /mnt/gluster  (FUSE client mount)
                                                  |
                     +-----------------+-----------------+
                     |                 |                 |
                 gluster-1         gluster-2         gluster-3      (Docker containers)
                  brick             brick             brick         replica-3 volume "files"
```

**Key design decisions (and the interview answers behind them)**

| Decision | Why |
|---|---|
| Files on GlusterFS, metadata in PostgreSQL | Each store does what it is good at. A distributed file system is bad for database workloads (latency, locking), so Postgres keeps its own local volume. |
| GlusterFS runs **next to** Kubernetes, not inside it | Kubernetes removed its built-in GlusterFS volume plugin in v1.26 and the Heketi provisioner is archived. The supported pattern is: storage cluster outside, mounted on the nodes. |
| App pods are **stateless** | Any pod can die or be duplicated without data loss; the state lives in GlusterFS and Postgres. |
| k3s via **k3d** | Real Kubernetes, light enough for one cloud machine (fits in 8-16 GB). |
| Replication **plus** backups | Replication protects against a dead node; it does not protect against a bad delete (the delete is replicated too). Backups to a separate store (MinIO) cover that. |

**Honesty rule (for the CV and interviews):** this is a lab-scale platform. All nodes run as containers on one cloud machine. Say "GlusterFS cluster and Kubernetes running as containers in a cloud environment", never "multi-region production".

---

## 3. Tools, and the job each one does

| Area | Tool | Real job |
|---|---|---|
| Storage | **GlusterFS** | Replicates every file on 3 nodes |
| OS | **Linux (Ubuntu / Debian)** | Base of everything |
| Backend | **FastAPI** (Python) | Upload / list / download / delete API |
| Frontend | **React + Vite**, served by **nginx** | The web page |
| Database | **PostgreSQL** (self-hosted) | File metadata (name, size, owner, checksum, date) |
| Containers | **Docker** | Packages each piece the same way everywhere |
| Orchestration | **Kubernetes (k3s via k3d)**, **kubectl** | Runs the app, self-heals, scales |
| Packaging | **Helm** | Installs Prometheus/Grafana/Loki/MinIO in one command each |
| Ingress | **Traefik** (bundled with k3s) | Routes web traffic to frontend / api |
| Scaling | **HPA** (Horizontal Pod Autoscaler) | Adds api pods under load |
| Config automation | **Ansible** | Builds the GlusterFS cluster (peers, volume, options), same result every time |
| Code + CI/CD | **Git, GitHub, GitHub Actions** | Tests, scans, builds images, runs the full end-to-end test |
| Registry | **GHCR** (GitHub Container Registry) | Stores the built images |
| Metrics | **Prometheus** + **node_exporter** + a GlusterFS metrics exporter | Collects health numbers |
| Dashboards | **Grafana** | Shows them |
| Alarms | **Alertmanager** | Fires on node down, split-brain, disk full, latency |
| Logs | **Loki** + **Grafana Alloy** | All container logs searchable in Grafana (Alloy replaces Promtail, which reached end of life in 2026) |
| Security (pipeline) | **Trivy**, **gitleaks**, **Bandit** | Image CVEs, leaked secrets, Python security bugs; CI fails on critical findings |
| Security (runtime) | **Kubernetes Secrets**, **NetworkPolicies**, **JWT auth** | No plaintext secrets, pods only talk to what they need, API requires login |
| Backups | **MinIO** (S3-compatible) + **restic** + `pg_dump` | Scheduled backups of files and database, restore drill |
| AIOps | **Python + scikit-learn** (Isolation Forest) | Learns normal storage latency/throughput, flags anomalies before a hard threshold trips |
| Load testing | **k6** | Generates traffic, proves autoscaling and measures failover impact |
| Cloud | **GitHub Codespaces** | Where the live platform runs |
| *Stretch* | **Argo CD** (GitOps), **Falco** | Git-driven deployments (matches Sofrecom #36); runtime threat detection |

---

## 4. Build order (slices)

A slice counts as **done** only when it runs from a clean start with one command, is checked automatically in CI, and has a short section in the README.

| # | Slice | Done when |
|---|---|---|
| **0** | **De-risk:** 3 GlusterFS containers, replica-3 volume, FUSE mount on the host, stop a node, file still readable | Green CI job `storage-smoke` |
| **1** | **Core:** k3d cluster + Postgres + FastAPI (upload/list/download, sha256 check) + Traefik ingress + failover test (stop gluster node, kill api pod) | Green CI job `e2e` |
| **2** | **Ansible:** GlusterFS cluster built by an Ansible playbook instead of shell | CI uses the playbook |
| **3** | **Frontend:** React page (upload, list, download, node status) | Served through the ingress, covered by e2e |
| **4** | **DevSecOps:** Trivy + gitleaks + Bandit gates, Kubernetes Secrets, NetworkPolicies, JWT login | CI blocks a planted vulnerability / secret |
| **5** | **Observability:** kube-prometheus-stack, GlusterFS exporter, Grafana dashboard, alerts, Loki + Alloy | Dashboard JSON in repo, alert fires in CI when a node is stopped |
| **6** | **Backups / DR:** MinIO + restic CronJob + pg_dump CronJob + restore drill script | Restore drill passes in CI |
| **7** | **AIOps:** anomaly-detector service reading Prometheus, exposing an anomaly score + alert | Injected slowdown is flagged |
| **8** | **Scale:** k6 load test + HPA | Pods scale up under load in CI |
| **9** | **Codespaces:** devcontainer (docker-in-docker, k3d, kubectl, helm), one-command `make up`, recorded demo | Opens and runs in a Codespace |
| 10 | *Stretch:* Argo CD GitOps, Falco | |

---

## 5. Where it runs (resources and free limits)

| Place | Use | Limits |
|---|---|---|
| **GitHub Actions** (ubuntu-latest) | Automated build + full end-to-end tests on every push | Private repo on GitHub Free: 2,000 min/month. Each full run should take 10-15 min |
| **GitHub Codespaces** | Live demo, manual exploring, recording | Free personal quota: 120 core-hours + 15 GB/month (≈60 h on a 2-core / 8 GB machine, ≈30 h on 4-core / 16 GB). Auto-stops when idle |
| Later (Student Pack or card) | Optional always-on deployment | Azure for Students / DigitalOcean credit / Oracle Always Free |

**Memory budget (target):** 3 GlusterFS containers ~1 GB, k3d (1 server + 2 agents) ~1.5 GB, app + Postgres ~0.5 GB, monitoring + Loki ~1.5 GB, MinIO ~0.3 GB. Total ~5 GB: fits a 8 GB Codespace, comfortable on 16 GB.

**Aziz's PC:** no Docker / WSL installed, 7.4 GB RAM. Not used for running the platform.

---

## 6. Repository layout

```text
ha-storage-platform/
├── README.md                  # what it is, diagram, demo, results
├── Makefile                   # make up / down / demo / test
├── docs/PLAN.md               # this file
├── docs/STATUS.md             # progress log, what's next
├── docs/INTERVIEW.md          # questions + answers Aziz must know
├── storage/                   # GlusterFS image, compose file, bootstrap
├── ansible/                   # playbook that builds the Gluster cluster
├── app/api/                   # FastAPI service + tests + Dockerfile
├── app/frontend/              # React + Vite + nginx Dockerfile
├── k8s/                       # manifests (kustomize): namespaces, postgres, api, frontend, ingress, hpa, netpol
├── observability/             # Helm values, dashboards, alert rules
├── backup/                    # MinIO values, restic + pg_dump CronJobs, restore drill
├── aiops/                     # anomaly detector service
├── loadtest/                  # k6 scripts
├── scripts/                   # cluster up/down, failover demo, smoke tests
├── .devcontainer/             # Codespaces config
└── .github/workflows/         # ci.yml (lint, test, scan, build, e2e)
```

---

## 7. CV wording by completion level (all true at the time they are used)

- **Slices 0-1 done:** "Highly available file-storage platform: replicated GlusterFS cluster (3 nodes) backing a FastAPI service on Kubernetes (k3s), PostgreSQL metadata, automated failover tests in GitHub Actions."
- **Slices 0-5 done:** add "security-gated CI/CD (Trivy, gitleaks, Bandit), Prometheus/Grafana/Loki observability with alerting."
- **All slices:** add "S3 backups with restore drills (MinIO, restic), ML anomaly detection on storage telemetry, autoscaling validated with k6, running in GitHub Codespaces."

Aziz has accepted the risk of listing it before every layer is finished. Mitigation: `docs/INTERVIEW.md` must be read and practised before any interview.

---

## 8. Risks

| Risk | Plan B |
|---|---|
| FUSE mount not allowed in a Codespace | Codespaces runs docker-in-docker with privileged containers; if `/dev/fuse` is unavailable, mount GlusterFS through its NFS export (NFS-Ganesha) instead |
| Mount propagation into k3d nodes | Mount on the host **before** creating the k3d cluster and bind-mount the path; if it fails, run the FUSE mount inside each k3d node container |
| CI minutes run out | Run the heavy e2e job only on `main` and manual dispatch; lint/scan on every push |
| Codespaces quota | Use a 2-core / 8 GB machine for routine work, 4-core only for recording; stop it when idle |
| Scope too big | Slices are independent; each finished slice is presentable on its own |
