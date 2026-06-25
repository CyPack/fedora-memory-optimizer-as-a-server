#!/usr/bin/env bash
# oomd-reconciler kurulum — 4 dependency gate + reboot-safe enable. Yeni server'a (mini-PC) taşınabilir.
# 2026-06-24 (cartographer V=0 blueprint). KURMADAN ÖNCE protected.conf'u bu host'a göre düzenle.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "✗ root olarak çalıştır: sudo ./install.sh"; exit 1; }
command -v setfattr getfattr docker >/dev/null 2>&1 || { echo "✗ GEREKLİ: 'attr' paketi (setfattr/getfattr) + docker"; exit 1; }
SDV="$(systemctl --version | awk 'NR==1{print $2}')"
[[ "$SDV" =~ ^[0-9]+$ && "$SDV" -ge 248 ]] || { echo "✗ GEREKLİ: systemd >= 248 (ManagedOOMPreference). Mevcut: $SDV"; exit 1; }
[[ "$(docker info --format '{{.CgroupVersion}}' 2>/dev/null)" == 2 ]] || { echo "✗ GEREKLİ: cgroup v2"; exit 1; }
systemctl is-active --quiet systemd-oomd || { echo "✗ GEREKLİ: systemd-oomd aktif olmalı"; exit 1; }
echo "✓ Tüm dependency gate'leri geçti (systemd $SDV, cgroup v2, oomd aktif, attr+docker var)"

HERE="$(cd "$(dirname "$0")" && pwd)"
install -Dm755 "$HERE/reconcile.sh"                   /usr/local/lib/oomd-reconciler/reconcile.sh
install -Dm755 "$HERE/oomd-reconciler-watch.sh"       /usr/local/bin/oomd-reconciler-watch.sh
install -Dm644 "$HERE/protected.conf"                 /etc/oomd-reconciler/protected.conf
install -Dm644 "$HERE/oomd-reconciler.service"        /etc/systemd/system/oomd-reconciler.service
install -Dm644 "$HERE/oomd-reconciler.timer"          /etc/systemd/system/oomd-reconciler.timer
install -Dm644 "$HERE/oomd-reconciler-events.service" /etc/systemd/system/oomd-reconciler-events.service

systemctl daemon-reload
systemctl enable --now oomd-reconciler.timer oomd-reconciler-events.service
systemctl start oomd-reconciler.service   # ilk reconcile hemen

echo "✓ Kuruldu + enable (reboot-safe)."
echo "  Doğrula: journalctl -t oomd-reconciler -n5"
echo "  Audit:   for s in /sys/fs/cgroup/system.slice/docker-*.scope; do getfattr -n user.oomd_omit \"\$s\" 2>/dev/null && echo \"\$s\"; done"
echo "  Rollback: systemctl disable --now oomd-reconciler.timer oomd-reconciler-events.service"
