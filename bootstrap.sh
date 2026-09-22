#!/usr/bin/env bash
#
# Socle minimal des VMs du lab.
#
# Ce script fait le strict necessaire pour qu'Ansible puisse prendre la main :
# un interpreteur Python. Tout le reste (paquets, utilisateurs, services, reseau)
# est du ressort des playbooks de la formation — c'est l'objet des TP.
#
# Appele par le Vagrantfile au premier `vagrant up`. Idempotent.

set -euo pipefail

log() { printf '[bootstrap] %s\n' "$*"; }

# --- 1. Interpreteur Python -------------------------------------------------
# Ansible exige Python 3.9+ sur le noeud gere (ansible-core 2.21).
# Debian 13 fournit Python 3.13, Rocky Linux 10 fournit Python 3.12.
if command -v python3 >/dev/null 2>&1; then
    log "python3 present : $(python3 --version 2>&1)"
else
    log "python3 absent, installation"
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq python3
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q python3
    else
        log "ERREUR : gestionnaire de paquets non reconnu"
        exit 1
    fi
    log "python3 installe : $(python3 --version 2>&1)"
fi

# --- 2. Acces sudo sans mot de passe pour l'utilisateur vagrant --------------
# Presume par les boxes Vagrant, revalide ici pour que `become` fonctionne
# des le premier playbook meme si la box a ete reconstruite.
if [ ! -f /etc/sudoers.d/99-vagrant-nopasswd ]; then
    log "configuration sudo NOPASSWD pour l'utilisateur vagrant"
    echo 'vagrant ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-vagrant-nopasswd
    chmod 0440 /etc/sudoers.d/99-vagrant-nopasswd
fi

log "socle pret sur $(hostname)"
