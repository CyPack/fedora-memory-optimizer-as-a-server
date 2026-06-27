# Agent orientation — fedora-memory-optimizer-as-a-server

This repo fixes broken Linux memory setups and hardens a host against memory-pressure
thrashing. It corrects the **v1 ZRAM+disk anti-pattern** (swappiness=180, zswap disabled).
Two profiles:

- **SERVER (core)** — zswap + tuned `systemd-oomd` + container OOM-protection reconciler.
- **DESKTOP (Layer 5, optional)** — browsers: kill a *tab*, not the whole browser + Claude Code
  log/swap hygiene.

## If a user asks you to "diagnose / migrate / install / set this up"

1. **Detect the profile first — READ-ONLY, never apply blind:**
   ```bash
   pgrep -a -i 'brave|chrom|firefox' | head     # browsers present → DESKTOP (also do Layer 5)
   cat /proc/sys/vm/swappiness                   # ==180 → broken v1 signature
   swapon --show; cat /sys/module/zswap/parameters/enabled
   ```
   - Server (no GUI/browsers) → follow **`.claude/agents/diagnoser.md`** (detect v1 → propose v2).
   - Desktop (browsers/GUI) → also **`.claude/agents/desktop-installer.md`** (install Layer 5).

2. **ALWAYS, before changing anything:** back up the files you'll touch, show the user the exact
   commands + expected before/after, and get **explicit confirmation**. Every layer has a rollback
   (README "Rollback", `desktop/install.sh` uninstall line) — offer it.

3. **Never commit or print secrets.** The Firefox `user.js` example is generic (no profile data).
   Don't hardcode anyone's `$HOME`, hostname, or IPs — the scripts use `$HOME` / systemd `%h`.

4. **Judge success by PSI**, not swap_used: `cat /proc/pressure/memory` → `full.avg10` ≈ 0 is healthy.
   High `swap_used` / `Committed_AS` alone is **not** a problem (browser/V8 virtual reservation).

Start at **`README.md`** (server `## Install`) and **`desktop/README.md`** (desktop layer).
Reboot is needed only for the zswap kernel cmdline; the desktop layer needs no reboot.
