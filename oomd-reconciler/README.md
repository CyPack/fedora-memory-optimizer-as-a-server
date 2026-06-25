# oomd-reconciler — systemd-oomd container OOM-protection (omit/avoid)

> ⚠️ **NOT YET TESTED in production.** Design-complete + evidence-graphed (Kubernetes controller pattern), but
> deploy deliberately on a non-critical host first.

## Problem
`systemd-oomd` SIGKILLs the heaviest cgroup under `system.slice` on memory pressure. With rootful Docker, all
containers live there → a stateful DB can be killed = data loss. `ManagedOOMPreference=omit` protects them, **but**
it's keyed to the container ID → **lost on redeploy/reschedule** (scope name = container ID).

## Solution: name-keyed reconciler (Kubernetes controller pattern)
- **Edge** (`docker events`) + **level** (systemd timer 30s resync) → idempotent reconcile.
- path-unit rejected: `/sys/fs/cgroup` is a pseudo-fs, not inotify-monitorable.
- Desired state = `protected.conf` (container name/regex/label) → observed = live scopes → apply missing omit.

## Install (per host — edit protected.conf first)
```bash
# edit protected.conf for YOUR critical containers
sudo ./install.sh   # checks gates: attr + docker + systemd>=248 + cgroup v2 + active systemd-oomd
journalctl -t oomd-reconciler -n5     # protected=N applied=A skipped=S errors=E
```

## Safety
Only mutation = `setfattr user.oomd_omit|avoid` on protected scopes. Never kills/reconfigures containers, never
changes oomd thresholds. `user.*` xattr needs only root file-ownership (not CAP_SYS_ADMIN). Self-cleaning.

**Rollback:** `systemctl disable --now oomd-reconciler.timer oomd-reconciler-events.service`; clear residue:
`for s in /sys/fs/cgroup/system.slice/docker-*.scope; do setfattr -x user.oomd_omit "$s" 2>/dev/null; done`

**Verify oracle = `getfattr`** (`oomctl` does NOT expose per-cgroup omit).

## Files
`reconcile.sh` (idempotent) · `oomd-reconciler-watch.sh` (edge) · `*.service`/`*.timer` (level) ·
`protected.conf` (per-host) · `install.sh` (gated, reboot-safe).

## Dependencies
`attr` (setfattr/getfattr) · docker · **systemd ≥ 248** (ManagedOOMPreference) · **cgroup v2** + active systemd-oomd.
Swarm/compose/plain-docker handled uniformly (all land in `/system.slice/docker-<id>.scope`).
