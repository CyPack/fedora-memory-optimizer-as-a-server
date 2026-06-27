# Desktop / Workstation layer (Layer 5)

**Optional companion to the server core.** The server layers (zswap + swappiness + tuned
`systemd-oomd` + reconciler) make a *server* resilient. A **desktop** has two extra needs the
server core deliberately does **not** cover:

1. **Browsers** — when memory runs low you want to lose **one tab**, not the whole browser.
2. **Agent/Claude Code cruft** — MCP debug logs and idle `claude` sessions silently pile up
   on disk and in swap during heavy daily use.

This layer adds both, reusing the core's own ideas (oom_score protection, oomd-omit thinking).

---

## Server vs Desktop — why earlyoom flips

| | Server core | Desktop layer |
|---|---|---|
| Primary killer | `systemd-oomd` (PSI, kills heaviest **cgroup**) | same for system; **but** browser cgroups need tab-granular handling |
| earlyoom | **disabled** (redundant, PSI-blind) | **re-enabled** — it's the process-level killer that honours `oom_score_adj` → kills one renderer (tab) |
| Why the difference | a server has no browsers; cgroup-kill of a runaway service is fine | a browser is ONE cgroup → oomd's cgroup-kill = whole browser dies (every tab) |

> **Not a contradiction — a different requirement.** On a server, killing the heaviest cgroup
> is the right move. On a desktop, the heaviest cgroup is often the browser, and you want
> tab-granularity, which only a process-level, `oom_score`-aware killer gives you.

---

## What's here

| Component | What it does | Privilege |
|---|---|---|
| `oom-browser-ladder.sh` + `.service` | tags browser **renderers (tabs) = +500** (first OOM victim), **main + GPU/utility/zygote helpers = 0** (protected). Firefox content left to Firefox's own per-tab management. IDEs never touched. Scans only browser PIDs → milliseconds. | root |
| `browser-memory-saver.md` | tier-1: Brave/Chromium "Memory Saver = Maximum" + Firefox `user.js` — discard idle tabs *before* any kill | user (UI) |
| `claude-code-hygiene/` | MCP-log rotator (daily, **2 GB hard cap** — never balloons) + stale-`claude`-session reaper (idle >24 h, frees swap; session history on disk is never touched) | user (systemd --user timers) |

### The 3-tier ladder

```
Tier 1  browser memory-saver       → discard idle tabs (no kill, instant reload)
Tier 2  oom-browser-ladder+earlyoom → under real pressure, kill ONE renderer (tab)
Tier 3  kernel OOM (renderer-weighted) → even the last-resort kill is a tab, never the app
        — the browser main + helpers stay protected at every tier —
```

---

## Install

```bash
# run as your normal user (uses sudo internally for the root parts)
./install.sh
```
Each part is independent — open `install.sh` and comment out anything you don't want
(e.g. skip `claude-code-hygiene` if you don't use Claude Code).

**Verify**
```bash
systemctl status oom-browser-ladder              # active
/usr/local/bin/oom-browser-ladder.sh --dry-run   # see renderer→500 / main→0 decisions
systemctl --user list-timers '*mcp*' '*stale*'   # CC hygiene timers
```

**Uninstall**
```bash
sudo systemctl disable --now oom-browser-ladder earlyoom
systemctl --user disable --now mcp-log-rotate.timer stale-claude-reap.timer
```

---

## Origin

Battle-derived on the same 15 GiB reference host as the server core: after the zswap migration,
heavy daily use still piled up 36 GB of MCP debug logs and ~6 GB of stale-`claude`-session swap,
and a memory spike would have taken down the whole browser. This layer makes that self-healing.
