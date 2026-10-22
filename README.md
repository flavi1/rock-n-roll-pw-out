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
| `--roc yes\|no` | `yes` | seconde sortie ROC (voir plus bas) ; `no` : rien n'est compilé ni installé pour ROC |
| `--default` | | fait de « Hifi » (RTP) la sortie par défaut |

Désinstallation : `bash rock-n-roll-pw-out/uninstall.sh` (`--purge` : aussi la configuration).

## Ce qui est installé (dans votre dossier personnel uniquement)

| Fichier | Rôle |
|---|---|
| `~/.config/rock-n-roll-pw-out/pw-out.conf` | configuration (conservée d'une installation à l'autre) |
| `~/.local/bin/rock-n-roll-pw-out` | commande : `apply`, `status`, `default`, `check` |
| `~/.config/systemd/user/rock-n-roll-out.service` | l'émetteur, dans un processus PipeWire à part, démarré avec la session |
| `~/.local/bin/rock-n-roll-roc`, `~/.config/systemd/user/rock-n-roll-out-roc.service` | ROC (optionnel) : programme compilé par `install.sh` et son service |
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

## ROC (optionnel, activé par défaut)

Une seconde sortie, **« Hifi — réseau (ROC 192 kHz) »**, pour un réseau imparfait
(Wi-Fi) : même format (192 kHz, flottant 32 bits, stéréo), mais un tampon plus grand
(80 ms) et, si la libroc du PC le permet, la **réparation des paquets perdus**
(Reed-Solomon). RTP reste la sortie de référence en Ethernet.

- `install.sh` installe `libroc-dev` et `gcc` (mot de passe `sudo` demandé une fois),
  puis compile le petit programme `rock-n-roll-roc`. En cas d'échec, ou avec
  `--roc no`, il n'y a simplement pas de sortie ROC : la sortie RTP n'est jamais
  touchée.
- Processus à part (service `rock-n-roll-out-roc`, redémarrages limités) : une panne
  de ROC n'affecte ni RTP ni le reste du son du PC.
- **Correction des pertes : seulement si la libroc du PC l'a.** Debian : oui.
  Ubuntu (24.04, 26.04) : non (bibliothèque OpenFEC absente). Le flux part alors
  sans correction (la Pi l'accepte aussi) : ROC n'apporte plus que son tampon.
- Même place que RTP sur la Pi : un seul émetteur à la fois, tous protocoles
  confondus. Choisir l'une **ou** l'autre sortie, pas les deux en même temps.
- Qualité : voir « Limitations connues ».

```
rock-n-roll-pw-out default roc     # ROC comme sortie par défaut
rock-n-roll-pw-out default         # retour à RTP
```

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
| Coupures en Ethernet (pas en Wi-Fi) ; sur la Pi, journal `unexpected seq` et moins de 1000 paquets/s reçus | paquets perdus par la carte réseau du PC, souvent l'économie d'énergie Ethernet (EEE), ex. cartes Intel `e1000e` : `sudo ethtool --show-eee eno1`, essai `sudo ethtool --set-eee eno1 eee off` (jusqu'au redémarrage). Permanent : voir « Couper l'EEE » ci-dessous |
| Son haché | `pw-top` pendant la lecture : la ligne `rock-n-roll-out` (pilote) doit être à 192000 ; sur la Pi, compter les paquets reçus (≈ 1000/s attendus) ; journal : `log-level = 3` dans `pw-out.conf`, `rock-n-roll-pw-out apply`, `journalctl --user -u rock-n-roll-out -f` ; Wi-Fi chargé : sur la Pi, `latency-ms` plus grand (`local.conf`) |

## Limitations connues

- **Aucune perte de paquet n'est tolérée.** Le son voyage sans compression et sans
  correction d'erreur : chaque paquet perdu (1 ms de son) provoque une
  resynchronisation de la Pi, donc une coupure audible. Le réseau doit livrer 100 %
  des paquets : ~1000 par seconde, 9,2 Mbit/s en continu. Un ping peut être parfait
  alors que ce flux régulier perd des paquets.
- **Économie d'énergie Ethernet (EEE) : cause fréquente de pertes.** Certaines cartes
  réseau (constaté : Intel `e1000e`, derrière une box SFR) perdent environ 13 % des
  paquets quand l'EEE est actif : coupures en Ethernet, alors qu'un autre PC en Wi-Fi
  passe sans problème. Remède : couper l'EEE sur le PC (voir « Couper l'EEE »
  ci-dessous). Ce réglage dépend de la carte et de la box : il n'est pas fait par
  cet outil.
- **Wi-Fi** : utilisable si le réseau est stable ; en cas de coupures, augmenter le
  tampon de la Pi (`latency-ms` dans son `local.conf`).
- **Une seule Pi par PC**, et un seul PC à la fois par Pi.
- **ROC n'est pas transparent.** Pour rattraper l'écart d'horloge entre le PC et
  la Pi, libroc rééchantillonne à la réception. À 192 kHz, seul son rééchantillonneur
  intégré fonctionne (Speex déborde au-delà de ~65 kHz). Il amplifie de +0,9 dB
  (corrigé par rock-n-roll-roc) et laisse un résidu de bruit et de distorsion
  d'environ −50 dB (≈ 0,3 %), mesuré sur un sinus de 1 kHz. RTP, lui, est sans
  perte, avec un rééchantillonnage PipeWire de qualité 10. ROC est donc un secours
  pour le Wi-Fi, pas la sortie hifi de référence.

## Couper l'EEE (économie d'énergie Ethernet) de façon permanente

Propre à la carte réseau et à la box, donc hors de cet outil.

1. Nom de la carte et état de l'EEE :
   ```
   ip -br link                                   # ex. eno1, enp3s0
   sudo ethtool --show-eee eno1 | grep status    # « enabled - active » : concerné
   ```
2. Essai, jusqu'au prochain redémarrage : `sudo ethtool --set-eee eno1 eee off`. Si
   les coupures disparaissent, le rendre permanent (étapes suivantes).
3. Vérifier que le réseau est géré par **NetworkManager** (Kubuntu, Ubuntu, Fedora…
   par défaut) :
   ```
   systemctl is-active NetworkManager            # doit répondre « active »
   nmcli -t -f DEVICE,STATE device | grep eno1   # doit répondre « eno1:connected »
   ```
   Sinon (systemd-networkd, ifupdown…) : le script ci-dessous ne sera pas lancé ;
   utiliser l'outil de votre système.
4. Un script relancé par NetworkManager à chaque connexion (démarrage, sortie de
   veille, câble rebranché). Remplacer `eno1` par le nom de la carte.
   `sudo nano /etc/NetworkManager/dispatcher.d/50-eee-off`, contenu :
   ```
   #!/bin/sh
   # Coupe l'EEE sur eno1 à chaque connexion (seulement s'il est actif :
   # le couper relance le lien)
   [ "$1" = "eno1" ] && [ "$2" = "up" ] || exit 0
   /usr/sbin/ethtool --show-eee eno1 | grep -q 'EEE status: enabled' && \
       /usr/sbin/ethtool --set-eee eno1 eee off
   exit 0
   ```
5. `sudo chmod 755 /etc/NetworkManager/dispatcher.d/50-eee-off`
6. Après un redémarrage : `sudo ethtool --show-eee eno1 | grep status` → `disabled`.

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
