#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Tests hors matériel : pw-out.conf, fichiers générés, options d'install.sh.
# Usage : bash tests/test-config.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD=(python3 "$HERE/files/rock-n-roll-pw-out")
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
FAILS=0
ok()   { echo "  ok   : $*"; }
fail() { echo "  FAIL : $*"; FAILS=$((FAILS+1)); }
export PW_OUT_CONF="$W/pw-out.conf"
cp "$HERE/pw-out.conf" "$PW_OUT_CONF"

echo "== check / generate (WirePlumber 0.5)"
"${CMD[@]}" check >/dev/null && ok "check" || fail "check"
"${CMD[@]}" generate "$W/g" 192.168.1.113 0.5 >/dev/null && ok "generate" || fail "generate"
S="$W/g/pipewire/rock-n-roll-out.conf"
grep -q 'libpipewire-module-rtp-sink' "$S" && ok "module rtp-sink" || fail "rtp-sink"
grep -q 'destination.ip = "192.168.1.113"' "$S" && ok "vers l'adresse résolue" || fail "destination.ip"
grep -q 'destination.port = 46000' "$S" && ok "port 46000 (= pw-in)" || fail "port"
grep -q 'audio.rate = 192000' "$S" && grep -q 'audio.format = "S24BE"' "$S" && ok "192 kHz / 24 bits" || fail "format"
grep -q 'rtp.ptime = 1' "$S" && grep -q 'sess.max-ptime = 1' "$S" && ok "paquets de 1 ms (1192 octets < 1280)" || fail "ptime"
grep -q 'media.class = "Audio/Sink"' "$S" && ok "sortie son visible" || fail "media.class"
grep -q 'node.always-process' "$S" && fail "hold = no : ne doit pas garder la place" || ok "place libérée quand rien ne joue"
grep -q 'ExecStartPre=%h/.local/bin/rock-n-roll-pw-out prepare' "$W/g/systemd/user/rock-n-roll-out.service" \
    && ok "adresse résolue à chaque démarrage" || fail "ExecStartPre"
grep -q 'default.clock.allowed-rates = \[ 44100 48000 88200 96000 176400 192000 \]' \
    "$W/g/pipewire/pipewire.conf.d/60-rock-n-roll-out.conf" && ok "fréquences autorisées" || fail "allowed-rates"
WP="$W/g/wireplumber/wireplumber.conf.d/60-rock-n-roll-out-spdif.conf"
grep -q 'audio.rate = 96000' "$WP" && ok "S/PDIF 96 kHz (règle WirePlumber 0.5)" || fail "S/PDIF 0.5"
[[ ! -e "$W/g/wireplumber/main.lua.d/60-rock-n-roll-out-spdif.lua" ]] && ok "pas de règle Lua en 0.5" || fail "Lua en 0.5"

echo "== WirePlumber 0.4 (Lua)"
"${CMD[@]}" generate "$W/g4" 192.168.1.113 0.4 >/dev/null
L="$W/g4/wireplumber/main.lua.d/60-rock-n-roll-out-spdif.lua"
grep -q '"alsa_output.\*iec958\*"' "$L" && grep -q '\["audio.rate"\] = 96000' "$L" && ok "règle Lua (motif glob)" || fail "Lua 0.4"
[[ ! -e "$W/g4/wireplumber/wireplumber.conf.d/60-rock-n-roll-out-spdif.conf" ]] && ok "pas de règle 0.5" || fail "0.5 en 0.4"
if command -v lua >/dev/null || command -v lua5.4 >/dev/null; then
    LUA="$(command -v lua || command -v lua5.4)"
    printf 'alsa_monitor = { rules = {} }\ndofile(arg[1])\nassert(#alsa_monitor.rules == 1)\n' > "$W/t.lua"
    "$LUA" "$W/t.lua" "$L" && ok "Lua exécutable" || fail "Lua invalide"
fi

echo "== options"
sed -i 's/^hold = no/hold = yes/; s/^spdif-rate = 96000/spdif-rate = no/' "$PW_OUT_CONF"
"${CMD[@]}" generate "$W/g2" 10.0.0.5 0.5 >/dev/null
grep -q 'node.always-process = true' "$W/g2/pipewire/rock-n-roll-out.conf" && ok "hold = yes : silence envoyé" || fail "hold"
[[ ! -e "$W/g2/wireplumber/wireplumber.conf.d/60-rock-n-roll-out-spdif.conf" ]] && ok "spdif-rate = no : S/PDIF non modifié" || fail "spdif no"
cp "$HERE/pw-out.conf" "$PW_OUT_CONF"

echo "== erreurs détectées"
bad() {  # bad "description" sed-expression
    cp "$HERE/pw-out.conf" "$PW_OUT_CONF"; sed -i "$2" "$PW_OUT_CONF"
    if "${CMD[@]}" check >/dev/null 2>&1; then fail "$1 non détecté"; else ok "$1 refusé"; fi
}
bad "fréquence invalide" 's/^rate = 192000/rate = 100000/'
bad "paquet trop gros (fragmentation)" 's/^ptime-ms = 1/ptime-ms = 2/'
bad "tampon non multiple" 's/^latency-ms = 10/latency-ms = 7/; s/^ptime-ms = 1/ptime-ms = 2/; s/^rate = 192000/rate = 48000/'
bad "option inconnue" 's/^hold = no/garder = no/'
cp "$HERE/pw-out.conf" "$PW_OUT_CONF"
sed -i 's/^rate = 192000/rate = 48000/; s/^ptime-ms = 1/ptime-ms = 2/; s/^latency-ms = 10/latency-ms = 10/' "$PW_OUT_CONF"
"${CMD[@]}" check >/dev/null 2>&1 && ok "48 kHz, paquets de 2 ms accepté" || fail "48 kHz / 2 ms refusé"

echo "== résolution"
python3 - "$HERE/files/rock-n-roll-pw-out" <<'PY' && ok "IP telle quelle, localhost résolu, nom inconnu -> échec" || fail "resolve"
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("o", sys.argv[1])
spec = importlib.util.spec_from_loader("o", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
assert m.resolve("192.168.1.113", 1) == "192.168.1.113"
assert m.resolve("localhost", 1) == "127.0.0.1"
assert m.resolve("nexistepas.invalid", 1) is None
assert m.glob_of(r"~alsa_output\..*iec958.*") == "alsa_output.*iec958*"
PY

echo "== install.sh : options écrites dans pw-out.conf"
export HOME="$W/home" XDG_CONFIG_HOME="$W/home/.config"
mkdir -p "$HOME"
# faux environnement : on s'arrête avant le démarrage
sed -e 's#^"\$BIN" check#exit 0#' "$HERE/install.sh" > "$W/inst.sh"
mkdir -p "$W/fakebin"
for b in pipewire wireplumber; do printf '#!/bin/sh\nexit 0\n' > "$W/fakebin/$b"; chmod +x "$W/fakebin/$b"; done
# module RTP absent ici : on neutralise ce test
sed -i 's#^if ! compgen -G "/usr/lib/\*/pipewire-0.3/libpipewire-module-rtp-sink.so"#if false \&\& ! compgen -G ""#' "$W/inst.sh"
cp -r "$HERE/files" "$HERE/pw-out.conf" "$W/"
if [[ $EUID -ne 0 ]]; then
    PATH="$W/fakebin:$PATH" bash "$W/inst.sh" --host 192.168.1.50 --port 46002 --hold yes >/dev/null 2>&1 || true
    C="$XDG_CONFIG_HOME/rock-n-roll-pw-out/pw-out.conf"
    grep -q '^host = 192.168.1.50' "$C" && grep -q '^port = 46002' "$C" && grep -q '^hold = yes' "$C" \
        && ok "--host / --port / --hold" || fail "options d'install.sh"
    PW_OUT_CONF="$C" "${CMD[@]}" check >/dev/null && ok "fichier modifié toujours valide" || fail "fichier modifié invalide"
else
    echo "  (root : test d'install.sh ignoré, il refuse sudo)"
fi

echo
echo "$FAILS échec(s)"
[[ $FAILS -eq 0 ]]
