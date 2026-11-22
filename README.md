# HA Storage Platform

A file-storage service that does not lose files and does not go down: a replicated **GlusterFS** cluster behind an application on **Kubernetes**, with observability, a security-gated CI/CD pipeline and backups. Built and tested in the cloud (GitHub Actions, GitHub Codespaces).

> Work in progress. Full plan: [`docs/PLAN.md`](docs/PLAN.md) · progress: [`docs/STATUS.md`](docs/STATUS.md)

## Status
| Slice | What | State |
|---|---|---|
| 0 | GlusterFS replica-3 cluster survives a node failure and self-heals | in progress |
| 1 | Kubernetes (k3s) + FastAPI + PostgreSQL + failover test | planned |
| 2–9 | Ansible, frontend, DevSecOps, observability, backups, AIOps, autoscaling, Codespaces | planned |

## Run the storage layer (Linux with Docker)
```bash
bash scripts/storage-up.sh      # 3 GlusterFS nodes + replica-3 volume
bash scripts/storage-mount.sh   # FUSE mount at /mnt/gluster
bash scripts/storage-smoke.sh   # write, kill a node, read back, heal
bash scripts/storage-down.sh --purge
```

## Scope note
Lab-scale: every node runs as a container on one cloud machine. It demonstrates replication, failover, self-healing and the operational tooling around them, not multi-region production.
