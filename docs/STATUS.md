# STATUS — progress log

Read this first when resuming. Newest entries at the top.

## Current state
- Slices 0, 1, 2 ✅ · Slice 3 (frontend) + 4 (DevSecOps) being validated · Slice 5 (observability) drafted (`storage/exporter.py`)
- Repo: local `C:\Users\AZYZ\Desktop\projects\ha-storage-platform` → GitHub `azyzex/ha-storage-platform` (private)
- Runs on: GitHub Actions (tests). Codespaces later (needs `gh auth refresh -h github.com -s codespace`, a browser step Aziz must do).
- Aziz's PC has no Docker/WSL → nothing runs locally.

## Waiting on Aziz
1. Pick 3 Sofrecom subjects (deadline 30 Nov) — see `PFE SUBMITTION/01_SUBJECTS/sofrecom.md`. Is Sfax OK?
2. GitHub Student Pack re-verification result.
3. Run `gh auth refresh -h github.com -s codespace` once (browser) so Codespaces can be driven from the CLI.
4. Confirm real months for the pentest + DiffServ projects on the CV (currently estimates: Oct 2026 / Nov 2026).

## Log
- 2026-11-22 — **Slice 1 PASSED** (run 45060920714): e2e on k3d. 10 MB upload/download identical; 3/3 replicas; gluster-3 stopped → file served in 0.07 s; API pod killed under load → **0/172 requests failed**; postgres-0 deleted → metadata intact.
- 2026-11-22 — **Slice 2 PASSED** (Ansible): pool + volume built by `ansible/site.yml`; second run changed=0. Bug found: volume create raced peer propagation ("Host gluster-3 is not in 'Peer in Cluster' state") → now waits for full membership on every node.
- 2026-11-22 — Test bug found: checksum compared mid self-heal → tests now wait for heal info = 0 entries.
- 2026-11-22 — **Slice 4 gates caught real issues**: Trivy flagged HIGH CVEs in python-multipart 0.0.20 / starlette 0.41.3 and 3 CRITICAL in nginx-unprivileged 1.27-alpine → bumped. gitleaks: no leaks.
- 2026-11-22 — Routing bug: with `/api` and `/` in one Ingress, API calls reached nginx (413 on upload; readiness check fooled by nginx's 200 index.html). Fixed with 2 Ingresses + explicit Traefik priorities; readiness now checks the JSON body.
- 2026-11-22 — **Slice 0 PASSED** in CI (run 45060618811): 3-node replica-3 volume, file readable 0.35 s after a node was stopped (identical sha256), node self-healed the missed write in ~6.5 s.
- 2026-11-22 — Slice 1 written (FastAPI + Postgres on k3d over the Gluster mount, e2e test), Slice 2 Ansible playbook drafted. Interview prep in `docs/INTERVIEW.md`.
- 2026-11-22 — Plan written (`docs/PLAN.md`). Environment checked: no Docker on PC, gh logged in as azyzex with repo+workflow scopes (no codespace scope).
