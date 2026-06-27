#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  oom-browser-ladder — DESKTOP OOM ladder: kill a TAB, not the whole browser    ║
# ║  Companion to fedora-memory-optimizer-as-a-server (Layer 5, desktop only)      ║
# ║  License: MIT                                                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# WHY THIS EXISTS (server vs desktop divergence):
#   The server core uses systemd-oomd, which SIGKILLs the heaviest *cgroup* under
#   pressure. On a server that is correct (kill a runaway service). On a DESKTOP a
#   browser is ONE cgroup, so oomd's cgroup-kill destroys the WHOLE browser (every
#   tab + the main process) when a single tab would have sufficed.
#
#   Tab-granular eviction needs a PROCESS-level killer that honours oom_score_adj
#   (kernel OOM-killer or earlyoom). This daemon sets oom_score_adj so that when
#   such a kill happens, the victim is a RENDERER (one tab) — never the browser
#   main process or its GPU/utility/network helpers (killing those crashes the app).
#
#   Pair this with earlyoom ENABLED on desktops (the server core disables it; on a
#   desktop it is the early, process-level, oom_score-respecting tab-killer). See
#   ../README.md "Server vs Desktop".
#
# WHAT IT DOES (read-only except writing /proc/PID/oom_score_adj, root):
#   • Chromium/Brave/Edge/Electron RENDERER  (cmdline has --type=renderer) → KILLABLE (+500)
#   • Browser MAIN process (no --type=, no -contentproc)                   → PROTECT  (0)
#   • Chromium helpers (--type=gpu-process/utility/zygote/broker/network)  → PROTECT  (0)
#   • Firefox: only the MAIN (comm=firefox) is protected; Firefox content
#     processes are LEFT ALONE — Firefox manages its own per-tab oom_score_adj
#     (foreground tab low, background high) which is SMARTER than a blanket value.
#   • IDEs/editors (code, idea, …) are NOT in the browser list → never touched.
#
# It scans ONLY browser processes (pgrep), so a pass is milliseconds — unlike a
# full /proc sweep which can take minutes on a loaded host.
#
# Usage:  oom-browser-ladder.sh            # daemon loop (systemd service)
#         oom-browser-ladder.sh --once     # single pass (testing/cron)
#         oom-browser-ladder.sh --dry-run  # print what it would set, change nothing
set -uo pipefail

INTERVAL="${OOM_LADDER_INTERVAL:-10}"           # seconds between passes (daemon mode)
RENDERER_SCORE="${OOM_LADDER_RENDERER_SCORE:-500}"
PROTECT_SCORE="${OOM_LADDER_PROTECT_SCORE:-0}"
# Browser / Electron comms whose RENDERERS are expendable (tabs). IDEs excluded on purpose.
# Override with OOM_LADDER_BROWSERS="brave|chromium|chrome".
BROWSERS_RE="${OOM_LADDER_BROWSERS:-^(brave|chrome|chromium|chromium-browse|google-chrome|opera|vivaldi|microsoft-edge|msedge|Discord|discord|slack|Slack|signal-desktop|element-desktop|telegram-desktop|WebKitWebProcess)$}"
FIREFOX_RE='^(firefox|firefox-bin|firefox-esr)$'

DRY=0; ONCE=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --once) ONCE=1;; esac; done

set_score() { # pid score label
  local pid="$1" score="$2" label="$3" cur
  cur=$(cat "/proc/$pid/oom_score_adj" 2>/dev/null) || return 0
  [ "$cur" = "$score" ] && return 0
  if [ "$DRY" = 1 ]; then printf '  [dry] pid=%-8s %4s→%-4s %s\n' "$pid" "$cur" "$score" "$label"; return 0; fi
  echo "$score" > "/proc/$pid/oom_score_adj" 2>/dev/null \
    && return 0 || { [ "$(id -u)" -ne 0 ] && echo "⛔ root gerekli (oom_score_adj yazimi)"; return 1; }
}

one_pass() {
  local changed=0
  # comm regex'i pgrep -f ile genis tarayip /proc/comm ile dogrula
  for pid in $(pgrep -f -i 'brave|chrom|chrome|opera|vivaldi|edge|firefox|discord|slack|signal-desktop|element-desktop|telegram-desktop' 2>/dev/null); do
    [ -d "/proc/$pid" ] || continue
    local comm cmd
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
    cmd=$(tr -d '\0' < "/proc/$pid/cmdline" 2>/dev/null) || continue

    # Firefox: yalniz ANA process'i koru; content'leri Firefox kendi yonetir → dokunma
    if [[ "$comm" =~ $FIREFOX_RE ]]; then
      if [[ "$cmd" != *"-contentproc"* ]]; then set_score "$pid" "$PROTECT_SCORE" "firefox-main(korundu)" && changed=$((changed+1)); fi
      continue
    fi
    # Chromium/Electron ailesi (renderer comm = tarayici adi). IDE'ler listede yok → atla.
    if [[ "$comm" =~ $BROWSERS_RE ]]; then
      if [[ "$cmd" == *"--type=renderer"* ]]; then
        set_score "$pid" "$RENDERER_SCORE" "renderer(tab)" && changed=$((changed+1))
      else
        # ana process VEYA gpu/utility/zygote/broker/network yardimcisi → koru
        set_score "$pid" "$PROTECT_SCORE" "main/helper(korundu)" && changed=$((changed+1))
      fi
    fi
  done
  [ "$DRY" = 1 ] && echo "  (dry-run) $changed degisiklik onerildi"
  return 0
}

if [ "$ONCE" = 1 ] || [ "$DRY" = 1 ]; then one_pass; exit 0; fi

# daemon loop
trap 'exit 0' SIGTERM SIGINT
while true; do one_pass; sleep "$INTERVAL"; done
