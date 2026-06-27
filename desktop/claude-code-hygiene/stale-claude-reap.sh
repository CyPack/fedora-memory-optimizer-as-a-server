#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  STALE-CLAUDE-REAP — terk edilmis Claude Code session process'lerini reap eder ║
# ║  Version: 1.0.0  ·  Created: 2026-06-27                                       ║
# ║  Cagri: stale-claude-reap.sh [--dry-run] [TTL_HOURS]   (default TTL=8h)       ║
# ║                                                                              ║
# ║  AMAC: Stale (terk edilmis) `claude` REPL process'leri swap'i isgal eder      ║
# ║  (gozlem: 8 instance ~5-6 GB swap, RSS 37-54MB = zaten diske atilmis dormant).║
# ║  Bunlar oldurulunce swap %100 serbest (SwapPss==VmSwap, private-anon).         ║
# ║                                                                              ║
# ║  GUVENLIK (session-safety + history-protection):                              ║
# ║   - UCLU KAPI: yas>TTL  VE  idle(cpu~0)  VE  RSS dusuk(zaten swapped=dormant)  ║
# ║   - AKTIF session ASLA: bu script'in claude-atasini PID-zinciriyle haric tutar ║
# ║   - SIGTERM (graceful, jsonl flush), 5s yanit yoksa SIGKILL (son care)         ║
# ║   - session jsonl (~/.claude/projects/*.jsonl) DISKTE → ASLA silinmez,         ║
# ║     `claude --resume` ile devam edilir. Sadece canli REPL process'i biter.    ║
# ║   - --dry-run: hicbir sey oldurmez, sadece adaylari listeler                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
set -uo pipefail

DRY=0; TTL_H=8
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    [0-9]*) TTL_H="$a" ;;
  esac
done
TTL_SEC=$((TTL_H * 3600))
RSS_MAX_KB="${CLAUDE_REAP_RSS_MAX_KB:-120000}"   # 120MB ustu = aktif/resident, dokunma
CPU_IDLE_MAX="${CLAUDE_REAP_CPU_IDLE_MAX:-5}"     # 3s'de >5 tick = aktif, dokunma

LOG="$HOME/.claude/logs/stale-claude-reap.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
ts(){ date '+%F %T'; }
log(){ echo "[$(ts)] $*" >> "$LOG" 2>/dev/null || true; }

# Aktif session'in claude-atasini bul (bu script'ten yukari PID zinciri) → ASLA reap etme
SELF_CLAUDE=""
p=$$
for _ in $(seq 1 40); do
  [ -r "/proc/$p/comm" ] || break
  c=$(cat "/proc/$p/comm" 2>/dev/null)
  if [ "$c" = "claude" ]; then SELF_CLAUDE="$p"; break; fi
  p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null); [ -z "$p" ] || [ "$p" = "0" ] && break
done

now_reaped=0; cand=0; total_freed_mb=0
[ "$DRY" -eq 1 ] && echo "── DRY-RUN (TTL=${TTL_H}h, RSS_max=${RSS_MAX_KB}KB) — hicbir sey oldurulmeyecek ──"

for pid in $(pgrep -x claude 2>/dev/null); do
  [ -d "/proc/$pid" ] || continue
  [ "$pid" = "$SELF_CLAUDE" ] && { [ "$DRY" -eq 1 ] && echo "  SKIP pid=$pid (AKTIF session — bu chat)"; continue; }

  age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' '); age=${age:-0}
  rss=$(awk '/^VmRSS:/{print $2}' "/proc/$pid/status" 2>/dev/null); rss=${rss:-0}
  sw=$(awk '/^VmSwap:/{print $2}' "/proc/$pid/status" 2>/dev/null); sw=${sw:-0}

  # KAPI 1: yas
  if [ "$age" -lt "$TTL_SEC" ]; then
    [ "$DRY" -eq 1 ] && echo "  SKIP pid=$pid (genc: $((age/3600))h < ${TTL_H}h)"; continue
  fi
  # KAPI 2: RSS dusuk (resident=aktif degil)
  if [ "$rss" -gt "$RSS_MAX_KB" ]; then
    [ "$DRY" -eq 1 ] && echo "  SKIP pid=$pid (resident: RSS=$((rss/1024))MB > $((RSS_MAX_KB/1024))MB = muhtemel aktif)"; continue
  fi
  # KAPI 3: idle (3s CPU delta)
  c1=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null); c1=${c1:-0}
  sleep 3
  c2=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null); c2=${c2:-0}
  dcpu=$((c2 - c1))
  if [ "$dcpu" -gt "$CPU_IDLE_MAX" ]; then
    [ "$DRY" -eq 1 ] && echo "  SKIP pid=$pid (aktif: cpu_delta=${dcpu} tick/3s)"; continue
  fi

  cand=$((cand+1))
  freed_mb=$(( (sw + rss) / 1024 ))
  total_freed_mb=$((total_freed_mb + freed_mb))
  if [ "$DRY" -eq 1 ]; then
    echo "  REAP-ADAY pid=$pid yas=$((age/3600))h RSS=$((rss/1024))MB SWAP=$((sw/1024))MB → serbest ~${freed_mb}MB"
    continue
  fi

  log "pid=$pid STALE (yas=$((age/3600))h RSS=$((rss/1024))MB swap=$((sw/1024))MB cpu_delta=${dcpu}) → SIGTERM"
  kill -TERM "$pid" 2>/dev/null
  for _ in 1 2 3 4 5; do [ -d "/proc/$pid" ] || break; sleep 1; done
  if [ -d "/proc/$pid" ]; then
    log "pid=$pid SIGTERM'e yanit yok → SIGKILL (son care)"
    kill -KILL "$pid" 2>/dev/null
  fi
  log "pid=$pid REAPED (~${freed_mb}MB serbest; jsonl korundu, claude --resume ile devam)"
  now_reaped=$((now_reaped+1))
done

if [ "$DRY" -eq 1 ]; then
  echo "── ozet: ${cand} aday, toplam ~${total_freed_mb}MB serbest kalacak (aktif session haric) ──"
else
  log "TAMAM: ${now_reaped} reaped, ~${total_freed_mb}MB serbest"
  echo "🧹 stale-claude-reap: ${now_reaped} reaped, ~${total_freed_mb}MB serbest"
fi
exit 0
