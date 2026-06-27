# Desktop OOM-Ladder Installer Agent (agent-friendly)

## Role
On a **desktop/workstation** (not a server), install the optional **Layer 5** so that under
memory pressure the machine loses **one browser tab**, not the whole browser — and so heavy
**Claude Code** use stops piling MCP logs onto disk and stale sessions into swap.

> Server vs desktop: the core repo disables `earlyoom` (oomd does cgroup-kill, fine for servers).
> A desktop **re-enables** it because a browser is one cgroup → oomd would kill the *whole*
> browser; `earlyoom` + the renderer-weighted `oom_score_adj` kill a single tab instead.
> This is a different requirement, not a contradiction. See `desktop/README.md`.

## Decide if this host wants it (read-only)
```bash
pgrep -a -i 'brave|chrom|firefox|electron' | head      # is this a desktop with browsers?
ls ~/.claude >/dev/null 2>&1 && echo "uses Claude Code" # CC hygiene applies?
du -sh ~/.cache/claude-cli-nodejs 2>/dev/null           # MCP-log bloat already present?
systemctl is-active earlyoom systemd-oomd               # current OOM managers
```
Desktop with browsers → install A+B (+D). Uses Claude Code → also install C.

## Preview what the ladder will do (no changes)
```bash
sudo desktop/oom-browser-ladder.sh --dry-run   # prints renderer→500 / main→0 per browser PID
```
Expect: every `--type=renderer` (tab) → 500; each browser MAIN + gpu/utility/zygote → 0;
Firefox content left alone (Firefox self-manages); IDEs untouched.

## Install (always back up + offer rollback first)
```bash
cd desktop && ./install.sh        # run as the normal user; uses sudo internally
```
Then tell the user the **manual tier-1** step it cannot script:
- Brave/Chromium: Settings → System → Memory → Memory Saver = ON, **Maximum**
- Firefox: apply `desktop/browser-memory-saver.md` prefs (about:config or `user.js`)

## Verify
```bash
systemctl status oom-browser-ladder                       # active
for p in $(pgrep -x brave); do echo "$p $(cat /proc/$p/oom_score_adj) \
  $(tr -d '\0' </proc/$p/cmdline | grep -oE -- '--type=[a-z-]+' | head -1)"; done
# → renderer lines = 500, main/zygote/gpu/utility lines = 0
systemctl --user list-timers '*mcp*' '*stale*'
```

## Output
A short report: is this a desktop? → which parts installed (A/B/C/D) → dry-run sample showing
renderer=500/main=0 → the two manual browser steps. **Never apply without explicit user
confirmation; never commit secrets; the Firefox `user.js` example is generic (no profile data).**
