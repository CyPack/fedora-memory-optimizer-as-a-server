# claude-code-hygiene — keep agent cruft out of disk & swap

Two user-level systemd timers for machines that run **Claude Code** heavily. Both are
read-only-safe and **never touch session history** (`~/.claude/projects/*.jsonl`).

## mcp-log-rotate
Claude Code writes a JSONL line for **every MCP tool call** to
`~/.cache/claude-cli-nodejs/*/mcp-logs-*` and **never deletes them** → on the reference host
this had grown to **36 GB / 80 k files**.

`mcp-log-rotate.sh` enforces, defense-in-depth:
- **time retention** — delete files older than `MCP_KEEP_DAYS` (default **7**)
- **hard size cap** — if the dir still exceeds `MCP_MAX_GB` (default **2**), delete the
  *oldest* files until under the cap → **mathematically cannot balloon again**
- path-guarded to `~/.cache/...mcp-logs-*` only (session JSONL is a different tree, untouched)

Timer: **daily**. Env overrides: `MCP_KEEP_DAYS`, `MCP_MAX_GB`, `MCP_LOGS_DIR`.

## stale-claude-reap
Idle/abandoned `claude` REPL processes sit in swap (on the reference host, 8 of them held
~6 GB). Killing one ends only the live REPL — the transcript is on disk, so `claude --resume`
brings it back.

`stale-claude-reap.sh` uses a **triple gate** so it only reaps the truly-abandoned:
- age **>** TTL (default 24 h via the timer; script default 8 h)
- RSS **<** `CLAUDE_REAP_RSS_MAX_KB` (default 120 MB — a resident/active session is bigger)
- idle (≈0 CPU over a 3 s sample)

…and it **never reaps the active session** (walks the PID chain from itself and excludes its
own `claude` ancestor). Graceful `SIGTERM` first (so `claude` can flush + reap its MCP
children → no orphans), `SIGKILL` only as last resort.

Timer: **every 6 h, TTL=24 h**. Test first with: `stale-claude-reap.sh --dry-run 24`.

## Install (handled by ../install.sh, or manually)
```bash
install -m755 *.sh ~/.claude/scripts/
install -m644 mcp-log-rotate.user.service   ~/.config/systemd/user/mcp-log-rotate.service
install -m644 mcp-log-rotate.user.timer     ~/.config/systemd/user/mcp-log-rotate.timer
install -m644 stale-claude-reap.user.service ~/.config/systemd/user/stale-claude-reap.service
install -m644 stale-claude-reap.user.timer   ~/.config/systemd/user/stale-claude-reap.timer
systemctl --user daemon-reload
systemctl --user enable --now mcp-log-rotate.timer stale-claude-reap.timer
```
