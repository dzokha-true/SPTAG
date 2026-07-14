# Rulings: 006-sptag-docker-build-verify (append-only, orchestrator-owned)

- 2026-07-14 RULING (dispatch): job runs via codex exec with
  `--sandbox danger-full-access` because docker requires the daemon socket
  outside the workspace sandbox. Compensating controls: host-access policy in
  the dispatch block (worktree + docker state only), builders-never-commit
  instruction, postflight touch-set audit against the frozen boundary set.
