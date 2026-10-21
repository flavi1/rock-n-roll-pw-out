# rock-n-roll-pw-out

Envoie le son d'un PC Linux (PipeWire : Kubuntu, Ubuntu, Fedora, Debian…) vers la
Raspberry Pi hifi par le réseau local, **sans perte et sans compression** :
RTP, 192 kHz / 24 bits. Côté Pi : [rock-n-roll-pw-in](https://github.com/flavi1/rock-n-roll-pw-in).

Une sortie **« Hifi — réseau (RTP 192 kHz) »** apparaît dans les réglages du son,
à côté de la carte son du PC : on choisit l'une, l'autre, ou on bascule à volonté.

## Installation

Sur le PC, **sans sudo**, avec votre compte habituel :

```
git clone https://github.com/flavi1/rock-n-roll-pw-out.git
bash rock-n-roll-pw-out/install.sh
```

Options (relancer `install.sh` pour en changer) :

| Option | Défaut | Rôle |
|---|---|---|
| `--host NOM\|IP` | `hifi.local` | la Pi ; un nom est résolu à chaque ouverture de session |
| `--port N` | `46000` | port de rock-n-roll-pw-in |
| `--hold yes\|no` | `no` | `yes` : ce PC garde la Pi même quand rien ne joue (envoi de silence) |
| `--default` | | fait de « Hifi » la sortie par défaut |

Désinstallation : `bash rock-n-roll-pw-out/uninstall.sh` (`--purge` : aussi la configuration).

## Ce qui est installé (dans votre dossier personnel uniquement)

| Fichier | Rôle |
|---|---|
| `~/.config/rock-n-roll-pw-out/pw-out.conf` | configuration (conservée d'une installation à l'autre) |
| `~/.local/bin/rock-n-roll-pw-out` | commande : `apply`, `status`, `default`, `check` |
| `~/.config/systemd/user/rock-n-roll-out.service` | l'émetteur, dans un processus PipeWire à part, démarré avec la session |
| `~/.config/pipewire/pipewire.conf.d/60-rock-n-roll-out.conf` | la sortie « Hifi » (sortie virtuelle à 192 kHz, sa propre horloge) et les fréquences autorisées : 44,1 à 192 kHz (remplace un ancien réglage à la main, ex. `50-96khz.conf`) |

## Fonctionnement

- Format **fixe** des deux côtés : 192 kHz / 24 bits / stéréo. La sortie « Hifi » est
  une sortie virtuelle qui a **sa propre horloge à 192 kHz**, indépendante de la carte
  son : ce que joue le PC (44,1 kHz, 48 kHz…) y est converti **une seule fois**,
  l'émetteur envoie ensuite tel quel. La Pi n'a jamais à changer de format : pas de
  coupure ni de renégociation entre deux morceaux.
- Les cartes son du PC ne sont pas touchées : elles gardent leur propre horloge et
  leur fréquence (pour en fixer une : voir plus bas).
- Paquets de 1 ms (1192 octets) : sous la taille d'un paquet réseau, aucune
  fragmentation. Débit : 9,2 Mbit/s (Ethernet 100 Mbit/s ou plus : sans souci).
- **Une Pi, un émetteur** : si un autre PC envoie déjà, la Pi ignore celui-ci jusqu'à
  5 s après la fin du son de l'autre. Quand rien ne joue, la sortie se met en veille
  et libère la place (sauf `--hold yes`).
- Pas de mot de passe : seul le réseau local est accepté par la Pi.

## État

```
rock-n-roll-pw-out status
```

```
  vers        : hifi.local, port UDP 46000
  format      : 192000 Hz S24BE 2 canaux, paquets de 1 ms (1192 octets), tampon 10 ms
  service     : active
  adresse     : 192.168.1.113
  sortie      : envoi en cours
  par défaut  : oui
```

## Dépannage

| Symptôme | Piste |
|---|---|
| `« hifi.local » introuvable` | Pi éteinte, ou résolution `.local` absente (paquet `libnss-mdns`) : `bash install.sh --host 192.168.1.113` |
| Sortie absente | `systemctl --user status rock-n-roll-out`, `journalctl --user -u rock-n-roll-out` |
| Pas de son sur la Pi | sur la Pi : `sudo rock-n-roll-pw-in status` (un autre PC tient la place ?) |
| Son haché | `pw-top` pendant la lecture : la ligne `rock-n-roll-out` (pilote) doit être à 192000 ; sur la Pi, compter les paquets reçus (≈ 1000/s attendus) ; journal : `log-level = 3` dans `pw-out.conf`, `rock-n-roll-pw-out apply`, `journalctl --user -u rock-n-roll-out -f` ; Wi-Fi chargé : sur la Pi, `latency-ms` plus grand (`local.conf`) |

## Fixer la fréquence d'une carte son (manuel, facultatif)

Propre à chaque installation, donc hors de cet outil. Exemple : une sortie numérique
S/PDIF (optique / coaxiale) vers un récepteur qui doit rester à 96 kHz.

1. Trouver le nom de la sortie : `wpctl status` (numéro de la carte dans « Sinks »),
   puis `wpctl inspect NUMÉRO | grep node.name` — par exemple
   `alsa_output.pci-0000_00_1f.3.iec958-stereo`.
2. Créer `~/.config/wireplumber/wireplumber.conf.d/50-carte-96khz.conf`
   (WirePlumber 0.5 ; version : `wireplumber --version`) :
   ```
   monitor.alsa.rules = [
     {
       matches = [ { node.name = "~alsa_output\\..*iec958.*" } ]   # ~ : expression régulière
       actions = { update-props = { audio.rate = 96000  audio.allowed-rates = [ 96000 ] } }
     }
   ]
   ```
3. `systemctl --user restart wireplumber pipewire pipewire-pulse`
4. Vérifier en jouant vers cette carte : `pw-top`, sa ligne doit afficher 96000.

Un ancien réglage global du type `default.clock.allowed-rates = [ 96000 ]`
(ex. `~/.config/pipewire/pipewire.conf.d/50-96khz.conf`) n'est plus utile : il fixe
tout le PC à 96 kHz, et `60-rock-n-roll-out.conf` le remplace pour permettre 192 kHz.

## Tests

```
bash tests/test-config.sh
```

## Licence

GPL-3.0-or-later
