# CLAUDE.md

Project-specific instructions for Claude Code in this repo.

See [AGENTS.md](./AGENTS.md) for the operational rundown on switching model
profiles, the difference between tracked `.sample` env templates and real
gitignored `.env*` files, and known deployment gotchas (Docker Compose
relative-path resolution, `--load-mode mlock` hangs on slow filesystems,
Windows/WSL2 port-exclusion errors). Read it before launching or debugging
any profile with `scripts/docker/launch-server.sh`.
