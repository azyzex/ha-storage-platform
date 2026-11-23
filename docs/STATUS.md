# STATUS — progress log

Read this first when resuming. Newest entries at the top.

## Current state
- Slices 0–8 ✅ + Argo CD ✅ + Falco ✅ (all in CI) · Slice 9 (Codespaces) being tested live
- Repo: local `C:\Users\AZYZ\Desktop\projects\ha-storage-platform` → GitHub `azyzex/ha-storage-platform` (private)
- Runs on: GitHub Actions (tests). Codespaces later (needs `gh auth refresh -h github.com -s codespace`, a browser step Aziz must do).
- Aziz's PC has no Docker/WSL → nothing runs locally.

## Waiting on Aziz
1. Pick 3 Sofrecom subjects (deadline 30 Nov) — see `PFE SUBMITTION/01_SUBJECTS/sofrecom.md`. Is Sfax OK?
2. GitHub Student Pack re-verification result.
3. Run `gh auth refresh -h github.com -s codespace` once (browser) so Codespaces can be driven from the CLI.
4. Confirm real months for the pentest + DiffServ projects on the CV (currently estimates: Oct 2026 / Nov 2026).

## Log
- 2026-11-23 — **Slice 9 (Codespaces) done + ALL GREEN (run 45090911082).** `make up` + every test passed live in a 4-core Codespace. Fixed on the way: /tmp default ACL blocked non-root pods (strip ACLs on Docker's data dir); SSH sessions lack GITHUB_TOKEN (read the Codespaces shared env file). Real screenshots in `docs/img/`.
- 2026-11-23 — **Bug: dashboard said 3/3 bricks with a node down.** `volume status` omits a disconnected peer's bricks, so the exporter kept the stale value 1. Exporter now judges every brick listed by `volume info`; the observability test requires GlusterBrickDown to fire.
- 2026-11-23 — **Bug: restarted node's brick never came back** (found by load + chaos with new heal diagnostics: Online N, 2,000+ entries pending). Stale brick PID file + PID reuse in the new container made glusterd think the brick was running. Entrypoint clears stale PID files and force-starts a brick still offline 25 s after start. Load after fix: 11,482 req, 0.01 % failed, p95 0.71 s, HPA 2→6, full heal.
- 2026-11-23 — Test timing fixes: Falco test waits for pods Ready and re-spawns the shell (probes attach seconds after "Loaded event sources"); wait_healed re-triggers heal every 30 s.
- 2026-11-22 — **ALL GREEN (run 45074247798)** incl. extras. Load: 12,431 req, 0 failed, p95 0.67 s, HPA 2→6, node killed mid-run (better than before: the exporter no longer runs the expensive `heal info` every 5 s). AIOps: 5→226 ms flagged in 42 s, static alert silent. Argo CD: NetworkPolicy restored 2 s, scale reverted 3 s, security setting 4 s. Falco: shell detected instantly, pod named.
- 2026-11-22 — **Slices 5b, 6, 7, 8 PASSED**: Loki+Alloy (131 log lines found); backup 11 s / restore after accidental delete 6 s; AIOps: 40 ms delay on one node → writes 10→294 ms, detector flagged in 49 s (z=74) while the 500 ms static alert stayed silent, cleared 66 s after; load: 7,436 req, 0.01% failed, p95 1.26 s, HPA 2→6 with gluster-3 killed 25 s mid-run.
- 2026-11-22 — Bugs found by the tests: disk pressure evicting pods (CI now frees ~25 GB + lab eviction thresholds); backup NetworkPolicy created 1 s before the job (moved with the other policies + pg_isready wait); Garage 2.x layout check; `heal info` too slow after thousands of writes → `heal-count` in tests and exporter.
- 2026-11-22 — Added Argo CD (GitOps self-heal test) and Falco (custom rule test) in a separate CI job; Codespaces devcontainer + Makefile + demo script.
- 2026-11-22 — **Slice 1 PASSED** (run 45060920714): e2e on k3d. 10 MB upload/download identical; 3/3 replicas; gluster-3 stopped → file served in 0.07 s; API pod killed under load → **0/172 requests failed**; postgres-0 deleted → metadata intact.
- 2026-11-22 — **Slice 2 PASSED** (Ansible): pool + volume built by `ansible/site.yml`; second run changed=0. Bug found: volume create raced peer propagation ("Host gluster-3 is not in 'Peer in Cluster' state") → now waits for full membership on every node.
- 2026-11-22 — Test bug found: checksum compared mid self-heal → tests now wait for heal info = 0 entries.
- 2026-11-22 — **Slice 4 gates caught real issues**: Trivy flagged HIGH CVEs in python-multipart 0.0.20 / starlette 0.41.3 and 3 CRITICAL in nginx-unprivileged 1.27-alpine → bumped. gitleaks: no leaks.
- 2026-11-22 — Routing bug: with `/api` and `/` in one Ingress, API calls reached nginx (413 on upload; readiness check fooled by nginx's 200 index.html). Fixed with 2 Ingresses + explicit Traefik priorities; readiness now checks the JSON body.
- 2026-11-22 — **Slice 0 PASSED** in CI (run 45060618811): 3-node replica-3 volume, file readable 0.35 s after a node was stopped (identical sha256), node self-healed the missed write in ~6.5 s.
- 2026-11-22 — Slice 1 written (FastAPI + Postgres on k3d over the Gluster mount, e2e test), Slice 2 Ansible playbook drafted. Interview prep in `docs/INTERVIEW.md`.
- 2026-11-22 — Plan written (`docs/PLAN.md`). Environment checked: no Docker on PC, gh logged in as azyzex with repo+workflow scopes (no codespace scope).
