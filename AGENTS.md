# Agent orientation (all agents — Codex, opencode, Gemini, …)

Full guidance is in **`CLAUDE.md`** (applies to every agent, not just Claude Code).

TL;DR:
1. **Detect profile (read-only first):** `pgrep -a -i 'brave|chrom|firefox'` → browsers ⇒ **desktop**;
   `cat /proc/sys/vm/swappiness` ⇒ `180` is the broken-v1 signature.
2. **Server** → follow `.claude/agents/diagnoser.md` (detect v1 → propose v2 zswap migration).
   **Desktop** → also `.claude/agents/desktop-installer.md` (Layer 5: browser tab-OOM ladder + CC hygiene).
3. **Back up + show commands + get explicit confirmation** before applying. Every layer has a rollback.
4. **Never leak secrets**; scripts use `$HOME` / `%h` (no hardcoded paths). Judge health by PSI
   `full.avg10` ≈ 0, not by swap_used.

Entry points: `README.md` (server install) · `desktop/README.md` (desktop layer) · `desktop/install.sh`.
