#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Desktop layer installer — fedora-memory-optimizer-as-a-server / desktop/      ║
# ║  Run as your NORMAL user (NOT sudo); it calls sudo only for the root parts.    ║
# ║  License: MIT                                                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Installs (each part is independent — comment out what you don't want):
#   A) oom-browser-ladder  (root systemd service)   → kill a TAB, not the whole browser
#   B) earlyoom ENABLED                              → process-level tab-killer (desktop only!)
#   C) claude-code-hygiene (user systemd timers)     → MCP log cap + stale-session reap
#   D) browser memory-saver                          → printed manual steps (UI, can't script)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ok(){ printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[1;33m!\033[0m %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] && { echo "Run as your normal user, not sudo (it uses sudo internally)."; exit 1; }

echo "── A) oom-browser-ladder (root service) ──"
sudo install -m 0755 "$HERE/oom-browser-ladder.sh" /usr/local/bin/oom-browser-ladder.sh
sudo install -m 0644 "$HERE/oom-browser-ladder.service" /etc/systemd/system/oom-browser-ladder.service
sudo systemctl daemon-reload
sudo systemctl enable --now oom-browser-ladder.service
ok "oom-browser-ladder.service active (browser renderers→500, main/helpers→protected)"

echo "── B) earlyoom ENABLED (desktop: process-level tab-killer) ──"
warn "Server core DISABLES earlyoom (oomd does cgroup-kill). Desktop RE-enables it because"
warn "oomd would kill the whole browser cgroup; earlyoom honours oom_score → kills one tab."
if ! command -v earlyoom >/dev/null 2>&1; then
  warn "earlyoom not installed — attempting install (Fedora: dnf)…"
  sudo dnf install -y earlyoom 2>/dev/null || warn "auto-install failed (non-Fedora? install earlyoom manually)"
fi
if command -v earlyoom >/dev/null 2>&1; then
  sudo systemctl enable --now earlyoom 2>/dev/null && ok "earlyoom active" || warn "earlyoom enable failed"
else
  warn "earlyoom unavailable — kernel OOM still kills tab-first (oom-browser-ladder weights renderers)"
fi

echo "── C) claude-code-hygiene (user timers — skip if you don't use Claude Code) ──"
if [ -d "$HOME/.claude" ]; then
  mkdir -p "$HOME/.claude/scripts" "$HOME/.config/systemd/user"
  install -m 0755 "$HERE/claude-code-hygiene/mcp-log-rotate.sh"   "$HOME/.claude/scripts/"
  install -m 0755 "$HERE/claude-code-hygiene/stale-claude-reap.sh" "$HOME/.claude/scripts/"
  install -m 0644 "$HERE/claude-code-hygiene/mcp-log-rotate.user.service"   "$HOME/.config/systemd/user/mcp-log-rotate.service"
  install -m 0644 "$HERE/claude-code-hygiene/mcp-log-rotate.user.timer"     "$HOME/.config/systemd/user/mcp-log-rotate.timer"
  install -m 0644 "$HERE/claude-code-hygiene/stale-claude-reap.user.service" "$HOME/.config/systemd/user/stale-claude-reap.service"
  install -m 0644 "$HERE/claude-code-hygiene/stale-claude-reap.user.timer"   "$HOME/.config/systemd/user/stale-claude-reap.timer"
  systemctl --user daemon-reload
  systemctl --user enable --now mcp-log-rotate.timer stale-claude-reap.timer
  ok "mcp-log-rotate.timer (daily, 2 GB hard cap) + stale-claude-reap.timer (6h, TTL=24h) active"
else
  warn "~/.claude not found — skipping Claude Code hygiene (install only if you use Claude Code)"
fi

echo "── D) browser memory-saver (manual, UI) ──"
echo "  Brave/Chromium : Settings → System → Memory → Memory Saver = ON, Maximum"
echo "  Firefox        : apply prefs from desktop/browser-memory-saver.md (about:config or user.js)"

echo
ok "Desktop layer installed. Verify: systemctl status oom-browser-ladder ; systemctl --user list-timers '*mcp*' '*stale*'"
echo "  Uninstall: sudo systemctl disable --now oom-browser-ladder earlyoom ; systemctl --user disable --now mcp-log-rotate.timer stale-claude-reap.timer"
