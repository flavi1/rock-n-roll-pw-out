#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# =============================================================================
#  rock-n-roll-pw-out — envoie le son de ce PC (PipeWire) vers la Raspberry Pi
#  (rock-n-roll-pw-in) par le réseau local : RTP 192 kHz / 24 bits, sans perte.
#
#  À lancer SANS sudo, avec votre compte (celui qui écoute la musique) :
#
#     bash install.sh [--host hifi.local] [--port 46000]
#                     [--hold yes|no] [--roc yes|no] [--default]
#
#  Ajoute une sortie « Hifi — réseau (RTP 192 kHz) » dans les réglages du son
#  (--default : en fait la sortie par défaut).
#  Idempotent : relancez-le pour changer une option ou mettre à jour.
#  Désinstallation : bash uninstall.sh
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rock-n-roll-pw-out"
CONF="$CFG_DIR/pw-out.conf"
BIN="$HOME/.local/bin/rock-n-roll-pw-out"
log()  { printf '\n\033[1;36m[rock-n-roll-pw-out]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mrock-n-roll-pw-out :\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "à lancer SANS sudo, avec votre compte habituel (le son est propre à chaque utilisateur)"

declare -A SET=()
MAKE_DEFAULT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host) SET[rtp.host]="${2:?}"; shift 2 ;;
        --port) SET[rtp.port]="${2:?}"; shift 2 ;;
        --hold) SET[rtp.hold]="${2:?}"; shift 2 ;;
        --roc) SET[roc.enabled]="${2:?}"; shift 2 ;;
        --default) MAKE_DEFAULT=1; shift ;;
        -h|--help) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "option inconnue : $1 (--help)" ;;
    esac
done

# --- Prérequis -----------------------------------------------------------------------
command -v pipewire >/dev/null || die "PipeWire n'est pas installé (Kubuntu / Ubuntu récents : présent par défaut)"
command -v wireplumber >/dev/null || die "WirePlumber n'est pas installé"
command -v python3 >/dev/null || die "python3 n'est pas installé"
if ! compgen -G "/usr/lib/*/pipewire-0.3/libpipewire-module-rtp-sink.so" >/dev/null && \
   ! compgen -G "/usr/lib*/pipewire-0.3/libpipewire-module-rtp-sink.so" >/dev/null; then
    die "module RTP de PipeWire absent : sudo apt install libpipewire-0.3-modules"
fi
systemctl --user is-active --quiet pipewire.service || \
    warn "PipeWire ne semble pas actif dans votre session"

# --- Configuration ----------------------------------------------------------------------
log "Configuration : $CONF"
mkdir -p "$CFG_DIR" "$(dirname "$BIN")"
# Le fichier de ce PC est conservé d'une installation à l'autre ; les options de la
# ligne de commande le modifient.
[[ -f "$CONF" ]] || install -m 644 "$HERE/pw-out.conf" "$CONF"
for k in "${!SET[@]}"; do
    python3 - "$CONF" "${k%%.*}" "${k#*.}" "${SET[$k]}" <<'PY'
import re, sys
path, sec, key, val = sys.argv[1:]
lines = open(path, encoding="utf-8").read().splitlines(True)
cur, done, out = None, False, []
for ln in lines:
    m = re.match(r"\s*\[([^\]]+)\]", ln)
    if m:
        if cur == sec and not done:
            out.append("%s = %s\n" % (key, val)); done = True
        cur = m.group(1).strip()
    elif cur == sec and not done and re.match(r"\s*%s\s*=" % re.escape(key), ln):
        ln = "%s = %s\n" % (key, val); done = True
    out.append(ln)
if not done:
    if cur != sec:
        out.append("\n[%s]\n" % sec)
    out.append("%s = %s\n" % (key, val))
open(path, "w", encoding="utf-8").write("".join(out))
PY
    echo "   $k = ${SET[$k]}"
done
install -m 755 "$HERE/files/rock-n-roll-pw-out" "$BIN"

# Ancien réglage de fréquence fait à la main (ex. 50-96khz.conf) : remplacé par le nôtre
for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/pipewire/pipewire.conf.d/*.conf; do
    [[ -f "$f" && "$(basename "$f")" != 60-rock-n-roll-out.conf ]] || continue
    if grep -q 'allowed-rates\|default.clock.rate' "$f"; then
        warn "$f règle aussi les fréquences : 60-rock-n-roll-out.conf, lu après, l'emporte"
    fi
done

# --- ROC (optionnel) -------------------------------------------------------------------
# Programme rock-n-roll-roc compilé ici (libroc + gcc). Échec : seule la sortie RTP
# existe, rien d'autre n'est touché. Recompilé si le source ou libroc change.
ROC_BIN="$HOME/.local/bin/rock-n-roll-roc"
ROC_SRC="$HERE/files/rock-n-roll-roc.c"
ROC_STAMP="$CFG_DIR/roc.stamp"
roc_deps_ok() { command -v gcc >/dev/null && pkg-config --exists roc 2>/dev/null; }
if "$BIN" check | grep -q '^  ROC         : désactivé'; then
    rm -f "$ROC_BIN" "$ROC_STAMP"
else
    log "ROC : programme rock-n-roll-roc (libroc)"
    if ! roc_deps_ok && command -v apt-get >/dev/null; then
        if [[ -t 0 ]]; then
            echo "   paquets nécessaires : gcc libc6-dev libroc-dev pkg-config (mot de passe sudo demandé ;"
            echo "   Ctrl+C puis « bash install.sh --roc no » pour s'en passer)"
            sudo apt-get install -y gcc libc6-dev libroc-dev pkg-config || warn "installation des paquets refusée ou impossible"
        else
            warn "paquets manquants : sudo apt install gcc libc6-dev libroc-dev pkg-config, puis relancer install.sh"
        fi
    fi
    if roc_deps_ok; then
        want="$(sha256sum "$ROC_SRC" | cut -d' ' -f1) $(pkg-config --modversion roc)"
        if [[ ! -x "$ROC_BIN" || "$(cat "$ROC_STAMP" 2>/dev/null)" != "$want" ]]; then
            # shellcheck disable=SC2046
            if gcc -std=c99 -O2 -Wall -o "$ROC_BIN.new" "$ROC_SRC" $(pkg-config --cflags --libs roc) -lm; then
                mv -f "$ROC_BIN.new" "$ROC_BIN"
                echo "$want" > "$ROC_STAMP"
                echo "   compilé (libroc $(pkg-config --modversion roc))"
            else
                rm -f "$ROC_BIN.new"
                warn "compilation impossible : ROC indisponible, la sortie RTP fonctionne normalement"
            fi
        else
            echo "   déjà à jour"
        fi
    else
        warn "libroc ou gcc absents : ROC indisponible, la sortie RTP fonctionne normalement"
        [[ -x "$ROC_BIN" ]] && echo "   (programme déjà compilé conservé)"
    fi
fi

# --- Démarrage --------------------------------------------------------------------------
log "Démarrage de l'envoi (PipeWire redémarre si les fréquences changent : coupure d'1 s)"
"$BIN" apply
[[ $MAKE_DEFAULT -eq 0 ]] || "$BIN" default

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
    warn "$HOME/.local/bin n'est pas dans le PATH : la commande est $BIN" ;;
esac
log "Terminé"
cat <<EOF
   Choisissez la sortie « $(sed -n 's/^description *= *//p' "$CONF" | head -1) » dans les
   réglages du son (KDE : icône du haut-parleur), ou : rock-n-roll-pw-out default
   ROC (si disponible) : sortie « Hifi — réseau (ROC 192 kHz) », ou : rock-n-roll-pw-out default roc
   État : rock-n-roll-pw-out status
EOF
