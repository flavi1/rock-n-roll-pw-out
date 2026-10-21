#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# rock-n-roll-pw-out — désinstallation (SANS sudo). Votre pw-out.conf est gardé
# sauf avec --purge.
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "À lancer SANS sudo."; exit 1; }
C="${XDG_CONFIG_HOME:-$HOME/.config}"
systemctl --user disable --now rock-n-roll-out.service 2>/dev/null || true
rm -f "$C/systemd/user/rock-n-roll-out.service" \
      "$C/pipewire/rock-n-roll-out.conf" \
      "$C/pipewire/pipewire.conf.d/60-rock-n-roll-out.conf" \
      "$C/wireplumber/wireplumber.conf.d/60-rock-n-roll-out-spdif.conf" \
      "$C/wireplumber/main.lua.d/60-rock-n-roll-out-spdif.lua" \
      "$HOME/.local/bin/rock-n-roll-pw-out"
[[ "${1:-}" != --purge ]] || rm -rf "$C/rock-n-roll-pw-out"
systemctl --user daemon-reload
echo "Redémarrage de PipeWire (fréquences et S/PDIF d'origine)"
systemctl --user restart wireplumber pipewire pipewire-pulse || true
echo "rock-n-roll-pw-out désinstallé."
