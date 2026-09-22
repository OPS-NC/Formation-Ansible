#!/usr/bin/env bash
#
# Socle minimal de l'equipement reseau du lab.
#
# VyOS n'est pas un invite reconnu par Vagrant : aucun greffon ne sait y poser
# une adresse IP. Sans ce script, les cartes host-only existent mais restent
# nues, et l'equipement n'est joignable que par le NAT — donc pas par
# l'inventaire du TP 13, qui l'attend sur son adresse de gestion.
#
# La configuration passe OBLIGATOIREMENT par le modele de script de VyOS.
# Un `ip addr add` ne survivrait pas au redemarrage et serait de toute facon
# ecrase par le systeme de configuration.
#
# Appele par le Vagrantfile avec l'adresse de gestion en argument, et SANS
# privileges : la configuration VyOS se fait sous le compte `vyos`. Lancee par
# root, elle laisse le systeme de configuration dans un etat ou toute commande
# ulterieure de l'utilisateur echoue sur un laconique "Set failed".
#
# Idempotent : `set` sur une valeur deja presente ne produit aucun changement.

set -euo pipefail

IP_GESTION="${1:?adresse de gestion attendue en premier argument}"

log() { printf '[bootstrap-vyos] %s\n' "$*"; }

log "configuration de eth1 : ${IP_GESTION}/24"

# eth2 est volontairement laissee NUE : la configurer est l'objet du TP 13.
#
# On ne touche PAS a `service ssh listen-address` : le restreindre a l'adresse
# de gestion couperait le NAT, et donc `vagrant ssh`.
/bin/vbash -s <<VYOS
source /opt/vyatta/etc/functions/script-template
configure
set interfaces ethernet eth1 address ${IP_GESTION}/24
commit
save
exit
VYOS

log "socle pret : $(ip -br addr show eth1 | tr -s ' ')"
