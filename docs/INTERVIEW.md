# Interview prep: questions and answers

> Read this before any interview where this project is on the CV. Each answer is short and in plain words; say it in your own words, don't recite. If a slice is not finished yet, say so honestly ("that part is in progress, here's how I'm designing it").

---

## The 30-second pitch
"I built a file-storage platform that keeps working when parts of it fail. Files are copied on 3 GlusterFS storage nodes, the application runs on Kubernetes, and I test the failures automatically in CI: I kill a storage node, an app pod under traffic and the database pod, and I measure that files stay available and identical. It all runs in the cloud on GitHub Actions and Codespaces."

---

## Storage (GlusterFS) — slice 0

**What is GlusterFS?**
A distributed file system: several servers ("nodes") each give a folder ("brick"), and Gluster joins them into one volume that clients mount like a normal disk.

**What does replica 3 mean?**
Every file is written to all 3 bricks. Any one node can die and the data is still complete on the other two.

**What happens when a node dies?**
The client (FUSE mount) notices the node is gone (I set `network.ping-timeout` to 5 s instead of the default 42 s) and keeps reading and writing on the 2 remaining nodes. Measured: the file was still read back with an identical checksum in 0.35 s.

**What happens when it comes back?**
Self-heal: Gluster sees the returning brick is missing writes and copies them back. Measured: about 6.5 s for the file written during the outage.

**What is split-brain?**
When two copies of a file changed independently and Gluster can't tell which one is right (e.g. network partition). Replica 3 uses quorum (2 of 3 must agree) to avoid it, which is one reason to use 3 copies and not 2.

**Why `force` when creating the volume?**
Because the bricks are on the container's main volume instead of a dedicated disk. Fine for a lab; in production each brick gets its own disk/partition.

**Replication vs backup?**
Replication protects against a dead node. It does NOT protect against a bad delete or corruption: the delete is replicated to all 3 copies instantly. That's why the plan adds real backups (MinIO + restic).

**Why are the nodes containers and not VMs?**
To fit a 3-node cluster on one cloud machine. The concepts (peers, bricks, replication, heal) are identical. Honest scope: it's a lab-scale cluster, not multi-region production.

---

## Application + Kubernetes — slice 1

**Architecture in one sentence?**
Stateless FastAPI pods on Kubernetes write file bytes to the GlusterFS mount and file details to PostgreSQL; Traefik routes traffic in.

**Why keep Postgres OFF GlusterFS?**
Databases do lots of small random writes and need precise file locking; a network file system adds latency and locking problems. So the database has its own local volume, and Gluster holds the big files.

**What does "stateless" mean and why does it matter?**
The API pod keeps nothing important in itself; files are in Gluster, metadata in Postgres. So any pod can serve any request, and pods can be killed, restarted or multiplied without losing data.

**How does Kubernetes use GlusterFS here?**
Kubernetes removed its built-in GlusterFS plugin (v1.26), so I use the supported pattern: the volume is mounted on the host with the GlusterFS client, then bind-mounted into every Kubernetes node; pods use it as a `hostPath` volume.

**What's k3s / k3d?**
k3s is a lightweight, certified Kubernetes. k3d runs k3s nodes as Docker containers, so a 3-node cluster fits on one machine.

**Readiness vs liveness probe?**
Liveness: "is the process alive?" (if not, restart it). Readiness: "can it serve traffic right now?" (checks the DB connection and that storage is writable; if not, Kubernetes stops sending it traffic but doesn't kill it).

**What happens when you kill an API pod?**
There are 2 replicas spread across nodes; the Service sends traffic to the healthy one while the Deployment creates a replacement. The e2e test measures how many requests failed during this (see CI summary).

**What happens when the database pod restarts?**
It's a StatefulSet with a persistent volume, so the data survives. The API's connection pool checks each connection before use, so it drops dead connections and reconnects automatically.

**How do you make uploads safe?**
Write to a temporary `.part` file, fsync, then rename (atomic), so nobody ever downloads a half-written file. I compute the sha256 while streaming and store it, so integrity can be checked later.

**Security basics already in place?**
API runs as a non-root user, read-only root filesystem, all Linux capabilities dropped, no privilege escalation. DB password is a Kubernetes Secret generated at deploy time, never in Git. Filenames are sanitized (path traversal blocked). Bandit scans the Python code in CI.

---

## CI/CD
**What runs on every push?**
Lint (ruff) + security scan (Bandit), API tests against a real Postgres, the GlusterFS failover test, then the full end-to-end test on a k3s cluster. Results are posted as a table in the GitHub job summary.

---

## Security (DevSecOps) — slice 4

**What do Trivy, gitleaks and Bandit each check?**
- **gitleaks**: secrets (passwords, keys, tokens) anywhere in the Git history.
- **Bandit**: security bugs in my Python code (e.g. shell injection, unsafe XML parsing).
- **Trivy**: known vulnerabilities (CVEs) in the container images' packages, AND risky settings in the Kubernetes files (e.g. containers running as root).

**Did it catch anything real?**
Yes. Trivy blocked the build on HIGH CVEs in `python-multipart` 0.0.20 (one allowed writing arbitrary files) and `starlette`, and on CRITICAL CVEs in the nginx base image. I upgraded the packages, moved to a newer nginx and added `apk upgrade` at build time. That's the point of a gate: it stopped vulnerable images before deployment.

**What are NetworkPolicies?**
Firewall rules inside Kubernetes. Default: deny all incoming traffic. Then I allow only what's needed: Traefik → web pods, API → Postgres, backup job → Postgres, Prometheus → API metrics. The test proves a random pod can't reach the database while a pod labelled as the API can.

**How are secrets handled?**
Generated at deploy time (`openssl rand`) into Kubernetes Secrets, never written in Git (gitleaks proves it). Pods read them as environment variables.

**What else is hardened?**
Every container runs as non-root, with a read-only filesystem, all Linux capabilities dropped and no privilege escalation, including Postgres (uid 70).

---

## Monitoring — slice 5

**How does Prometheus get the metrics?**
It "scrapes" HTTP endpoints every 10-15 s: the API's `/metrics` (found through a ServiceMonitor), and my GlusterFS exporter on each storage node.

**Why did you write your own GlusterFS exporter?**
The official one (gluster-prometheus) is unmaintained. Mine is ~100 lines of Python: it runs the gluster CLI on each node and exposes brick status, connected peers, files waiting for heal and free space.

**What happens when a storage node dies?**
Prometheus can't reach its exporter, so `up == 0`; the `GlusterNodeDown` rule fires after 20 s of that. Measured end to end: ~36-48 s from the node stopping to the alert firing (scrape interval + evaluation + the 20 s "for"). It reaches Alertmanager, which can route it to email/Slack/Telegram, and it resolves ~15 s after the node is back.

**What is the storage probe?**
Each API pod writes, fsyncs and reads a small file on GlusterFS every 5 s and records the time. That's storage latency as the application feels it (measured ~40-76 ms per replicated write+fsync).

**Logs?**
Loki stores them, Grafana Alloy collects them from every pod through the Kubernetes API (Alloy replaced Promtail, which is end-of-life). Logs and metrics are in the same Grafana.

---

## Backups — slice 6

**Why backups if you already have 3 replicas?**
Replication protects against a dead node, not a mistake: a delete or a corruption is copied to all 3 replicas instantly. The drill proves it: delete a file → gone from all 3 bricks → restored from the backup with the same checksum.

**How does the backup work?**
A nightly Kubernetes CronJob: an init container runs `pg_dump`, then restic backs up the dump plus every file (read-only mount), encrypted, to Garage (S3-compatible). Retention: 7 daily, 4 weekly.

**Why Garage and not MinIO?**
MinIO stopped publishing its community container images in 2025. Running an unmaintained image would contradict the security gates, so I chose Garage, a maintained, lightweight S3-compatible store.

**RPO / RTO?**
RPO (how much data you can lose) = up to 24 h with a nightly backup; RTO (how long to restore) = measured by the drill (seconds for this data size). For a real system you'd back up more often and test restores regularly — which the drill does in CI on every push.

---

## AIOps — slice 7

**What does the anomaly detector do?**
It reads storage signals from Prometheus every 15 s (write/read latency, heal backlog, offline bricks), learns what normal looks like for this system, and flags samples that don't fit, using an Isolation Forest (scikit-learn).

**Why not just a threshold?**
Thresholds miss "gray failures": a node that's slow but alive. Example from the test: one node gets 40 ms of network delay, every replicated write gets several times slower, but stays under the 500 ms static alert. The detector flags it and says which signal moved (z-score of write latency).

**What is an Isolation Forest, simply?**
It builds many random trees that split the data. Normal points need many splits to isolate; unusual points are isolated quickly. Fewer splits = more anomalous.

**Limits (say them before they ask)?**
It learns only from what it saw since it started; a real version would train on weeks of history and account for daily patterns. I also require a real shift in at least one signal (z-score > 4) so it doesn't fire on noise.

---

## Load + autoscaling — slice 8

**What does the load test show?**
k6 ramps to 40 users uploading, listing and downloading files. The HorizontalPodAutoscaler adds API pods when CPU passes 60%. In the middle of the load a storage node is killed for 25 s, and the run must still keep failures under 1% and p95 under 2 s.

**How does the HPA decide?**
metrics-server reports each pod's CPU; the HPA compares the average to the target (60% of the CPU request) and computes how many pods are needed, between 2 and 6. Scale-down waits 2 minutes to avoid flapping.

**What is preStop for?**
When a pod is deleted it keeps serving 5 s while it's removed from the Service and Traefik. Without it, 2 of 128 requests failed during a pod kill; with it, 0.
