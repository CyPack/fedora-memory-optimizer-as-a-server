#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  MCP-LOG-ROTATE — Claude Code MCP debug log'larini KURSUN-GECIRMEZ sinirlar    ║
# ║  Version: 1.0.0  ·  Created: 2026-06-27                                       ║
# ║  Cagri: mcp-log-rotate.sh [--verbose]   (systemd --user timer: her 6 saat)    ║
# ║                                                                              ║
# ║  SORUN: CC her MCP cagrisini ~/.cache/claude-cli-nodejs/*/mcp-logs-* altina   ║
# ║  jsonl yazar, ASLA silmez → kontrolsuz buyur (gozlem: 36GB / 80.000 dosya).   ║
# ║                                                                              ║
# ║  ID GARANTI (defense-in-depth):                                               ║
# ║    1. TIME-retention: KEEP_DAYS'ten eski dosyalar silinir (default 7g)         ║
# ║    2. SIZE-CAP (sert tavan): toplam > MAX_GB ise EN ESKI dosyalar, tavan       ║
# ║       altina inene kadar silinir → mcp-logs ASLA MAX_GB'i gecemez (default 2G) ║
# ║    3. bos mcp-logs-* dizinleri temizlenir                                      ║
# ║                                                                              ║
# ║  IRON: yalniz ~/.cache/.../mcp-logs-* (disposable). session-history            ║
# ║  (~/.claude/projects/*.jsonl) FARKLI dizin → ASLA dokunulmaz (path-guard).     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
set -uo pipefail
VERBOSE=0; [[ "${1:-}" == "--verbose" ]] && VERBOSE=1
say(){ [[ "$VERBOSE" -eq 1 ]] && echo "$@"; }
LOG="${HOME}/.claude/logs/mcp-log-rotate.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log(){ echo "[$(date '+%F %T')] $*" >> "$LOG" 2>/dev/null || true; }

DIR="${MCP_LOGS_DIR:-$HOME/.cache/claude-cli-nodejs}"
KEEP_DAYS="${MCP_KEEP_DAYS:-7}"
MAX_GB="${MCP_MAX_GB:-2}"
MAX_KB=$(( MAX_GB * 1024 * 1024 ))

# PATH-GUARD: yanlislikla baska dizini budamayi engelle
if [[ "$DIR" != *"/.cache/"* || ! -d "$DIR" ]]; then
  log "ABORT: gecersiz/guvensiz DIR=$DIR (yalniz ~/.cache altinda calisir)"
  echo "⛔ mcp-log-rotate: gecersiz DIR ($DIR) — atlandi"; exit 0
fi

before_kb=$(du -sk "$DIR" 2>/dev/null | cut -f1 || echo 0)

# ── 1. TIME-retention ─────────────────────────────────────────────────────────
find "$DIR" -path '*mcp-logs-*' -type f -mtime +"$KEEP_DAYS" -delete 2>/dev/null || true

# ── 2. SIZE-CAP (sert tavan): hala buyukse en ESKI dosyalari sil ──────────────
cur_kb=$(du -sk "$DIR" 2>/dev/null | cut -f1 || echo 0)
capped=0
if (( cur_kb > MAX_KB )); then
  # oldest-first (mtime artan), tavan altina inene kadar sil
  while IFS= read -r line; do
    (( cur_kb <= MAX_KB )) && break
    size_kb=$(( $(echo "$line" | cut -d' ' -f1) / 1024 ))
    path=$(echo "$line" | cut -d' ' -f2-)
    rm -f "$path" 2>/dev/null && { cur_kb=$(( cur_kb - size_kb )); capped=$((capped+1)); }
  done < <(find "$DIR" -path '*mcp-logs-*' -type f -printf '%T@\t%s\t%p\n' 2>/dev/null | sort -n | awk -F'\t' '{print $2" "$3}')
fi

# ── 3. bos mcp-logs-* dizinleri ───────────────────────────────────────────────
find "$DIR" -type d -name 'mcp-logs-*' -empty -delete 2>/dev/null || true

after_kb=$(du -sk "$DIR" 2>/dev/null | cut -f1 || echo 0)
freed_mb=$(( (before_kb - after_kb) / 1024 ))
REPORT="OK mcp-logs=$((after_kb/1024))MB (was=$((before_kb/1024))MB, freed=${freed_mb}MB, cap=${MAX_GB}G, keep=${KEEP_DAYS}g, size-capped=${capped}f)"
log "$REPORT"
echo "🧹 mcp-log-rotate: $REPORT"
exit 0
