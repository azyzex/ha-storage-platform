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

## Questions to expect on later slices (prepare as they get built)
- How do Prometheus and Grafana get the metrics? What alert fires when a node dies?
- What does Trivy check vs gitleaks vs Bandit?
- How do you restore from a backup and how did you test it?
- How does the anomaly detector decide something is abnormal (Isolation Forest)?
- How does the HPA decide to add pods?
