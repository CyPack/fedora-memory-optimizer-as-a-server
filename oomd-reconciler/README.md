# oomd-reconciler — Extended Package (systemd-oomd container OOM-protection)

> ## ⚠️⚠️ STATUS: NOT YET TESTED IN PRODUCTION ⚠️⚠️
> This is an **extended / optional** layer on top of the base memory architecture. It is **design-complete and
> evidence-graphed** (every decision below is sourced), and the reconcile logic is idempotent + non-destructive
> (it only writes one xattr). **But it has not been run on a live production fleet yet.** Deploy it deliberately:
> test on a non-critical host first, watch `journalctl -t oomd-reconciler`, and keep the rollback handy.

---

## Why this package exists (the problem)

`systemd-oomd` relieves memory pressure by SIGKILL-ing the heaviest cgroup under a monitored slice **before** the
kernel OOM-killer locks the machine up. That's good. But with **rootful Docker**, every container is a cgroup under
`system.slice` — so under pressure, oomd can kill a **stateful DB container** (Postgres/Redis/MinIO) = **data loss**.

`systemd-oomd` supports `ManagedOOMPreference=omit` (remove a cgroup from the kill candidate pool) via a
`user.oomd_omit` extended attribute on the cgroup. **The catch:** the cgroup is `docker-<container-id>.scope`, and
the container ID **changes on every recreate / compose-update / swarm reschedule** → a one-shot `omit` is **orphaned
exactly when it matters** (a redeployed DB has a new ID with no protection).

**This package solves that** with a *name-keyed reconciler*: you declare protection by container **name/label**
(stable), and a controller continuously re-applies `omit` to whatever container ID currently matches.

---

## Design rationale (every choice is sourced)

**Architecture = Kubernetes controller pattern: edge-triggered + level-triggered, idempotent reconcile.**

| Decision | Why | Source |
|---|---|---|
| **NOT a systemd `path-unit`** | `/sys/fs/cgroup` is a *pseudo-filesystem* — inotify cannot reliably watch it, so new `docker-*.scope` creation may never fire `IN_CREATE`. `systemd.path` inherits inotify's limits. | [inotify(7)](https://man7.org/linux/man-pages/man7/inotify.7.html), [systemd.path(5)](https://man.archlinux.org/man/systemd.path.5), [systemd#20198 (missed cgroup event)](https://github.com/systemd/systemd/issues/20198) |
| **Edge = `docker events`** (low latency) | reacts instantly on container `start` — but its buffer caps at the last 1000 events and isn't guaranteed across daemon restart → can miss, so it's only a *hint* | [docker system events (1000-buffer)](https://docs.docker.com/reference/cli/docker/system/events/) |
| **Level = systemd timer (30s resync)** | re-reads full state, reboot-safe (`Persistent=true` catches missed runs); the safety net that makes missed edges harmless | [systemd.timer(5)](https://man.archlinux.org/man/systemd.timer.5) |
| **Idempotent reconcile from current state** | exactly how `kube-controller-manager` works (informer edge + periodic resync) — the decision is always derived from observed state, never from the event payload | [Kubernetes controllers — watch + resync](https://kubernetes.io/docs/concepts/architecture/controller/) |
| **`user.oomd_omit` xattr is honored here** | both the monitored ancestor (`/system.slice`) and the docker scopes are `root:root` → systemd-oomd's same-owner UID-match rule is satisfied | [systemd.resource-control(5) — ManagedOOMPreference](https://man.archlinux.org/man/systemd.resource-control.5), [systemd PR #23764 (all cgroups)](https://github.com/systemd/systemd/pull/23764) |
| **xattr governed by file perms (not CAP_SYS_ADMIN)** | `user.*` xattrs only need root file-ownership → minimal privilege; xattrs are non-recursive and self-clean when the scope disappears | [systemd PR #19007 (omit/avoid xattr design)](https://github.com/systemd/systemd/pull/19007), [xattr(7)](https://man7.org/linux/man-pages/man7/xattr.7.html) |

---

## Install (per host — edit `protected.conf` FIRST)
```bash
# 1. Edit protected.conf for YOUR critical containers (name / regex / swarm-service / compose-service)
# 2. Install (gated + reboot-safe):
sudo ./install.sh
#    gates checked: attr(setfattr/getfattr) + docker + systemd>=248 + cgroup v2 + active systemd-oomd
# 3. Verify:
journalctl -t oomd-reconciler -n5        # -> protected=N applied=A skipped=S errors=E
for s in /sys/fs/cgroup/system.slice/docker-*.scope; do getfattr -n user.oomd_omit "$s" 2>/dev/null && echo "$s"; done
```

## Safety (cannot do harm)
The **only** mutation is `setfattr user.oomd_omit|avoid` on protected scopes. It never kills, restarts, or
reconfigures a container; never changes oomd thresholds; never touches non-`user.*` xattrs. A protected container
that disappears takes its xattr with it (no orphans).

**Rollback:**
```bash
sudo systemctl disable --now oomd-reconciler.timer oomd-reconciler-events.service
for s in /sys/fs/cgroup/system.slice/docker-*.scope; do sudo setfattr -x user.oomd_omit "$s" 2>/dev/null; done
```

**Verification oracle = `getfattr`.** Note: `oomctl` does **not** expose per-cgroup omit — don't rely on it for proof.

## Files
| File | Role |
|---|---|
| `reconcile.sh` | idempotent reconcile (getfattr-guarded; writes only omit/avoid xattr) |
| `oomd-reconciler-watch.sh` | edge watcher (`docker events` → trigger reconcile, debounced) |
| `oomd-reconciler.service` | oneshot reconcile (shared by timer + events) |
| `oomd-reconciler.timer` | level-triggered 30s resync (Persistent, reboot-safe) |
| `oomd-reconciler-events.service` | edge watcher service |
| `protected.conf` | **per-host** list of containers to protect |
| `install.sh` | gated, reboot-safe installer |

## Dependencies
`attr` (setfattr/getfattr) · docker · **systemd ≥ 248** (ManagedOOMPreference added in 248) · **cgroup v2** +
active `systemd-oomd`. Swarm / compose / plain-docker handled uniformly (all land in `/system.slice/docker-<id>.scope`;
only the `protected.conf` match-type differs). On swarm, run one copy per node (omit is node-local).

## References (full list)
- [systemd.resource-control(5)](https://man.archlinux.org/man/systemd.resource-control.5) — `ManagedOOMPreference`, `user.oomd_omit`/`avoid`, UID-match, non-recursive xattr
- [systemd PR #19007](https://github.com/systemd/systemd/pull/19007) — omit/avoid xattr design
- [systemd PR #23764](https://github.com/systemd/systemd/pull/23764) — honor preference on all cgroups (same-owner)
- [systemd-oomd(8)](https://man.archlinux.org/man/systemd-oomd.8) — candidate selection, leaf/oom.group eligibility
- [inotify(7)](https://man7.org/linux/man-pages/man7/inotify.7.html) — pseudo-filesystems (/proc, /sys) not monitorable
- [systemd.path(5)](https://man.archlinux.org/man/systemd.path.5) · [systemd#20198](https://github.com/systemd/systemd/issues/20198) — inotify cgroup miss
- [docker system events](https://docs.docker.com/reference/cli/docker/system/events/) — 1000-event buffer cap
- [systemd.timer(5)](https://man.archlinux.org/man/systemd.timer.5) — `OnUnitActiveSec` / `Persistent`
- [xattr(7)](https://man7.org/linux/man-pages/man7/xattr.7.html) — user namespace governed by file permissions
- [Kubernetes controllers](https://kubernetes.io/docs/concepts/architecture/controller/) — watch + periodic resync pattern
