# Fedora Memory Optimizer — as a Server

**Server-grade Linux memory management.** zswap (compressed swap) + tuned `systemd-oomd` (PSI pressure-response)
+ container OOM-protection reconciler. Portable across servers; battle-derived from a real swap-thrashing incident
on a 15 GiB / 69-container host.

> ⚠️ **Status:** The core layers (zswap + swappiness + oomd-tuning + earlyoom-off) are **applied & verified live**.
> The `oomd-reconciler/` package is **NOT YET TESTED in production** — design-complete, evidence-graphed, but
> deploy it deliberately. See its own README.

---

## Why this exists — the v1 mistake it fixes

This is the **corrected successor** to the older "Universal/Fedora Memory Optimizer v1" (ZRAM + disk-swap, never-kill
philosophy). That v1 *causes* the exact thrashing it claims to prevent. If your machine runs v1, an agent reading
this repo can detect the broken signature and migrate you.

| # | v1 (broken) | Why it's wrong | v2 (this repo) |
|---|---|---|---|
| 1 | **ZRAM=RAM/2 (prio 100) + disk swapfile (prio 30)** | **LRU inversion** — ZRAM fills with cold pages while the active working set is pushed to slow disk. *(Chris Down / Meta: "do not run zram alongside disk swap.")* | **zswap** (compressed **cache in front of** disk swap; LRU writeback, no dead-fill) |
| 2 | `vm.swappiness = 180` | tuned for zram-only; with a disk swapfile it = aggressive disk thrashing | `vm.swappiness = 60` |
| 3 | `vm.page-cluster = 0` | disables readahead on the disk swapfile | `vm.page-cluster = 3` |
| 4 | **`zswap.enabled=0`** (actively disabled!) | the single biggest error — zswap is the *correct* tool, turned off | **`zswap.enabled=1`** (zstd, zsmalloc, max_pool 20%) |
| 5 | "never-kill" / trust kernel OOM | `systemd-oomd` left passive (e.g. 90%/1min) → never fires until kernel lock-up | `systemd-oomd` tuned (**60% / 20s**) + `earlyoom` disabled (redundant, PSI-blind) + score-protection daemon kept |
| 6 | no container OOM protection | a stateful DB container can be SIGKILL'd under pressure | `oomd-reconciler/` (omit/avoid xattr, redeploy-safe) |

---

## Architecture (v2 — layered, server-grade)

```
Layer 1  zswap (zstd, max_pool 20%)   → compression in front of swapfile (macOS "memory compression" equivalent)
Layer 2  swappiness=60 / page-cluster=3 → balanced eviction for zswap+disk
Layer 3  systemd-oomd tuned (PSI)     → proactive pressure-kill BEFORE kernel lock-up (macOS "memory pressure")
Layer 4  oomd-reconciler               → stateful containers (DBs) removed from oomd's kill pool, redeploy-safe
Layer 5  desktop/ (optional)           → browsers: kill a TAB not the whole browser + Claude Code log/swap hygiene
Observe  PSI (/proc/pressure/memory) + atop  → watch PRESSURE, not swap_used (macOS "Memory Pressure" analogue)
```

**Key insight:** swap *used* being high is **not** a problem if **PSI `full.avg10` ≈ 0**. Watch pressure, not the number.

---

## Before → After (measured on the reference host, 15 GiB RAM)

| Metric | v1 (broken) | v2 (this) |
|---|---|---|
| swap-out spikes (`so`, vmstat) | **45036** | **0** (max ~256) |
| swap used | 51 GiB (climbing) | 27 GiB (stable) |
| `PSI memory.full.avg10` | rising | **0.00** (green) |
| zram | 100% full, idle (LRU-inverted) | removed |
| OOM managers | 3 conflicting (earlyoom+oomd+custom) | 2 (oomd tuned + score-protection) |

---

## Install (each layer; review before applying — needs root, reboot for cmdline)

```bash
# 1) zswap ON, zram OFF, swappiness 60  (GRUB/grubby example)
sudo grubby --update-kernel=ALL --remove-args="zswap.enabled=0"
sudo grubby --update-kernel=ALL --args="zswap.enabled=1 zswap.compressor=zstd zswap.zpool=zsmalloc zswap.max_pool_percent=20"
sudo truncate -s0 /etc/systemd/zram-generator.conf          # disable zram (NOT `touch` — that is a no-op)
printf '[OOM]\nSwapUsedLimit=90%%\nDefaultMemoryPressureLimit=60%%\nDefaultMemoryPressureDurationSec=20s\n' \
  | sudo tee /etc/systemd/oomd.conf.d/99-tuned.conf
echo 'vm.swappiness=60'    | sudo tee /etc/sysctl.d/99-zswap.conf
echo 'vm.page-cluster=3'   | sudo tee -a /etc/sysctl.d/99-zswap.conf
sudo systemctl disable --now earlyoom 2>/dev/null || true   # redundant where systemd-oomd is active
sudo sysctl --system && sudo systemctl reload systemd-oomd
# reboot to activate zswap cmdline + drop zram

# 2) (optional, NOT YET TESTED) container OOM protection
cd oomd-reconciler && sudo ./install.sh
```

**Verify after reboot:** `zramctl` (empty) · `swapon --show` (only swapfile) · `cat /sys/module/zswap/parameters/enabled` (Y)
· `cat /proc/sys/vm/swappiness` (60) · `cat /proc/pressure/memory` (full avg10 → 0).

**Rollback:** `grubby --remove-args` the zswap args + re-add `zswap.enabled=0`; restore `zram-generator.conf`;
`rm /etc/systemd/oomd.conf.d/99-tuned.conf /etc/sysctl.d/99-zswap.conf`; `systemctl enable --now earlyoom`.

---

## Desktop / Workstation (Layer 5, optional)

The server core is for servers. A **desktop** needs two things it deliberately omits:
**(1)** when memory runs low, lose **one browser tab**, not the whole browser;
**(2)** stop heavy **Claude Code** use from piling MCP debug logs onto disk and idle sessions into swap.

See **[`desktop/`](desktop/)** — `./desktop/install.sh` (run as your user) sets up:
- `oom-browser-ladder` — tags browser **renderers (tabs) = first OOM victim**, **main + GPU/utility helpers = protected**
- **earlyoom re-enabled** (desktop only) — the process-level killer that honours `oom_score` → kills one tab
  *(the server core disables earlyoom; a desktop needs it because oomd's cgroup-kill would take the whole browser — see [`desktop/README.md`](desktop/README.md))*
- `claude-code-hygiene/` — MCP-log rotator (daily, **2 GB hard cap**) + stale-session reaper (history never touched)
- Brave/Firefox memory-saver guide ([`desktop/browser-memory-saver.md`](desktop/browser-memory-saver.md))

---

## Lessons (problems → root cause → fix)

- **"swap fills every minute"** → not a leak; ZRAM+disk LRU inversion + swappiness=180. → zswap + swappiness 60.
- **"committed memory 98 GB on 15 GB RAM"** → *false alarm* (browser/V8 virtual reservation; real anon ~5 GB).
  → judge by PSI, not Committed_AS.
- **oomd "never fires"** → a `passive-nokill` drop-in (90%/1min) masked it. → tune to 60%/20s.
- **earlyoom present but 0 kills in 7 days** → PSI-blind, redundant beside systemd-oomd. → disable.
- **stateful DB could be SIGKILL'd** → containers live under `system.slice` (rootful Docker). → reconciler `omit`,
  but protection is container-ID-keyed and lost on redeploy → needs the name-keyed reconciler (level+edge).

## Golden path
`zswap (compression) → swappiness/page-cluster (eviction) → systemd-oomd tuned (pressure-kill) → reconciler (container protect) → observe via PSI`.

---

## Agent-friendly
Drop this repo at a coding agent and ask it to diagnose / install:
- `.claude/agents/diagnoser.md` — **auto-detects the v1 broken signature** (swappiness=180 + ZRAM+disk +
  `zswap.enabled=0`) on any host and proposes this v2 migration.
- `.claude/agents/desktop-installer.md` — on a **desktop**, installs the optional Layer 5 (browser tab OOM
  ladder + Claude Code hygiene). Both back up + ask for confirmation; neither commits secrets.

## License
MIT — see `LICENSE`.
