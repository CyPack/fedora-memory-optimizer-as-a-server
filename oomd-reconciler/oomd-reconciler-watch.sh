#!/usr/bin/env bash
# Edge watcher: docker 'start' event -> reconcile tetikle (debounced; reconcile full state re-okur, coalesce güvenli).
set -euo pipefail
docker events --filter type=container --filter event=start --format '{{.ID}}' \
| while read -r _; do
    systemctl start --no-block oomd-reconciler.service
  done
