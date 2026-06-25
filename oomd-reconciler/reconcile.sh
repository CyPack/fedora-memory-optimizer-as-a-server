#!/usr/bin/env bash
# oomd-reconciler: idempotent reconcile — protected.conf'taki container'lara user.oomd_omit/avoid uygula.
# SADECE omit/avoid xattr yazar. Container'a/oomd-config'e DOKUNMAZ. 2026-06-24 (cartographer V=0 blueprint).
set -euo pipefail
CONF="${OOMD_RECONCILER_CONF:-/etc/oomd-reconciler/protected.conf}"
CG=/sys/fs/cgroup/system.slice
prot=0 appl=0 skip=0 err=0

resolve_ids() {  # "match-type:value" -> current container full-IDs (observed state)
  local t="${1%%:*}" v="${1#*:}"
  case "$t" in
    name)            docker ps --no-trunc -q -f "name=^${v}$" ;;
    name-regex)      docker ps --no-trunc --format '{{.ID}} {{.Names}}' | awk -v r="$v" '$2 ~ r {print $1}' ;;
    swarm-service)   docker ps --no-trunc -q -f "label=com.docker.swarm.service.name=${v}" ;;
    compose-service) docker ps --no-trunc -q -f "label=com.docker.compose.service=${v}" ;;
    *)               logger -t oomd-reconciler "WARN unknown match-type: $t" ;;
  esac
}

while read -r match pref _; do
  [[ -z "${match:-}" || "$match" == \#* ]] && continue
  case "$pref" in omit|avoid) ;; *) logger -t oomd-reconciler "WARN bad pref '$pref' for $match"; continue ;; esac
  xattr="user.oomd_${pref}"
  for cid in $(resolve_ids "$match"); do
    prot=$((prot+1)); scope="$CG/docker-${cid}.scope"
    [[ -d "$scope" ]] || { err=$((err+1)); logger -t oomd-reconciler "WARN no scope for $cid ($match)"; continue; }
    if getfattr -n "$xattr" "$scope" >/dev/null 2>&1; then skip=$((skip+1))            # idempotent
    elif setfattr -n "$xattr" -v 1 "$scope" 2>/dev/null; then appl=$((appl+1))         # apply missing
    else err=$((err+1)); logger -t oomd-reconciler "ERROR setfattr failed $scope"; fi
  done
done < "$CONF"

logger -t oomd-reconciler "reconcile protected=$prot applied=$appl skipped=$skip errors=$err"
echo "protected=$prot applied=$appl skipped=$skip errors=$err"
