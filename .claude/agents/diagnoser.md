# Memory Diagnoser Agent (agent-friendly auto-migration)

## Role
Detect the **v1 broken memory-optimizer signature** on a host and propose the v2 (zswap server-grade) migration.

## Detect the broken signature (read-only)
```bash
cat /proc/sys/vm/swappiness                         # == 180  → BROKEN
swapon --show                                        # zram0 (prio 100) AND a disk swapfile → LRU-inversion
cat /sys/module/zswap/parameters/enabled             # N/0 while zram present → zswap wrongly disabled
grep -rl 'swappiness = 180\|Never-Kill\|passive-nokill' /etc/sysctl.d /etc/systemd/oomd.conf.d 2>/dev/null
oomctl 2>/dev/null | grep -i pressure                # 90% / 1min → oomd passive (never fires)
systemctl is-active earlyoom                          # active + 0 kills → redundant
```
**Verdict = BROKEN if:** swappiness 180 **and** (zram + disk swap) **and** zswap disabled.

## Confirm it's actually thrashing (not a false alarm)
```bash
vmstat 2 5      # high si≈so (symmetric) = thrashing;  so spikes (40k+) = aggressive eviction
cat /proc/pressure/memory   # full.avg10 — THIS is the health metric, NOT swap_used
```
Note: high `Committed_AS` / `swap_used` alone is **not** proof — judge by PSI `full.avg10`.

## Propose v2 migration
Follow the root README `## Install` steps: zswap ON + zram OFF + swappiness 60 + page-cluster 3 +
oomd tuned 60%/20s + earlyoom off + (optional, untested) oomd-reconciler. Always back up + offer rollback first.

## Output
A short report: detected signature → which v1 errors are present → exact v2 commands → expected before/after
(so 45036→0, swap stabilizes, PSI→0). Never apply without explicit user confirmation.
