# STATUS — progress log

Read this first when resuming. Newest entries at the top.

## Current state
- Slice 0 ✅ · Slice in progress: **1 (Kubernetes core)**, then 2 (Ansible)
- Repo: local `C:\Users\AZYZ\Desktop\projects\ha-storage-platform` → GitHub `azyzex/ha-storage-platform` (private)
- Runs on: GitHub Actions (tests). Codespaces later (needs `gh auth refresh -h github.com -s codespace`, a browser step Aziz must do).
- Aziz's PC has no Docker/WSL → nothing runs locally.

## Waiting on Aziz
1. Pick 3 Sofrecom subjects (deadline 30 Nov) — see `PFE SUBMITTION/01_SUBJECTS/sofrecom.md`. Is Sfax OK?
2. GitHub Student Pack re-verification result.
3. Run `gh auth refresh -h github.com -s codespace` once (browser) so Codespaces can be driven from the CLI.
4. Confirm real months for the pentest + DiffServ projects on the CV (currently estimates: Oct 2026 / Nov 2026).

## Log
- 2026-11-22 — **Slice 0 PASSED** in CI (run 45060618811): 3-node replica-3 volume, file readable 0.35 s after a node was stopped (identical sha256), node self-healed the missed write in ~6.5 s.
- 2026-11-22 — Slice 1 written (FastAPI + Postgres on k3d over the Gluster mount, e2e test), Slice 2 Ansible playbook drafted. Interview prep in `docs/INTERVIEW.md`.
- 2026-11-22 — Plan written (`docs/PLAN.md`). Environment checked: no Docker on PC, gh logged in as azyzex with repo+workflow scopes (no codespace scope).
