# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Formation Ansible — lab complet.
#
# Toutes les machines de la formation sont definies ici. Aucune VM n'est creee
# a la main ni depuis une ISO.
#
#   vagrant up                                     lab J1 / J2 (4 VMs, ~6 Go)
#   vagrant up k3s-master k3s-node01 k3s-node02    lab J3      (3 VMs, ~5 Go)
#   vagrant status                                 etat des machines
#   vagrant halt / vagrant destroy -f              arret / remise a zero
#
# Reseau host-only 192.168.56.0/24 (plage autorisee par defaut par VirtualBox
# depuis la 6.1.28 : 192.168.56.0/21 — aucun /etc/vbox/networks.conf requis).

# Les versions de box sont EPINGLEES. Deux raisons :
#   1. Reproductibilite : tous les stagiaires travaillent sur le meme systeme.
#   2. bento/rockylinux-10 est passee de BIOS+SATA (10.0) a EFI+VirtIO SCSI (10.1).
#      Sans epinglage, le comportement depend du cache local de chaque poste.
#
# ATTENTION : le registre HCP Vagrant ferme le 31/12/2026 (plus de publication
# depuis le 01/10/2026). Mirrorez les fichiers .box en interne avant cette date
# et utilisez :box_url + :box_download_checksum.
BOX_DEBIAN         = "bento/debian-13"
BOX_DEBIAN_VERSION = "202510.26.0"      # Debian 13.1, Python 3.13
BOX_ROCKY          = "bento/rockylinux-10"
BOX_ROCKY_VERSION  = "202512.01.0"      # Rocky 10.1, Python 3.12, EFI

servers = [
  # --- Lab jours 1 et 2 -----------------------------------------------------
  {
    :hostname => "web01",
    :ip       => "192.168.56.11",
    :box      => BOX_DEBIAN,
    :version  => BOX_DEBIAN_VERSION,
    :ram      => 1024,
    :cpu      => 1
  },
  {
    :hostname => "web02",
    :ip       => "192.168.56.12",
    :box      => BOX_DEBIAN,
    :version  => BOX_DEBIAN_VERSION,
    :ram      => 1024,
    :cpu      => 1
  },
  {
    :hostname => "db01",
    :ip       => "192.168.56.21",
    :box      => BOX_ROCKY,
    :version  => BOX_ROCKY_VERSION,
    :ram      => 2048,
    :cpu      => 2
  },
  {
    :hostname => "tools",
    :ip       => "192.168.56.31",
    :box      => BOX_DEBIAN,
    :version  => BOX_DEBIAN_VERSION,
    :ram      => 2048,
    :cpu      => 2
  },

  # --- Lab jour 3 : cluster k3s ---------------------------------------------
  # Non demarrees par `vagrant up` afin de menager la RAM du poste pendant J1/J2.
  {
    :hostname  => "k3s-master",
    :ip        => "192.168.56.41",
    :box       => BOX_DEBIAN,
    :version   => BOX_DEBIAN_VERSION,
    :ram       => 2048,
    :cpu       => 2,
    :autostart => false
  },
  {
    :hostname  => "k3s-node01",
    :ip        => "192.168.56.42",
    :box       => BOX_DEBIAN,
    :version   => BOX_DEBIAN_VERSION,
    :ram       => 1536,
    :cpu       => 2,
    :autostart => false
  },
  {
    :hostname  => "k3s-node02",
    :ip        => "192.168.56.43",
    :box       => BOX_DEBIAN,
    :version   => BOX_DEBIAN_VERSION,
    :ram       => 1536,
    :cpu       => 2,
    :autostart => false
  },
# Troisieme worker — decommenter sur un poste disposant de 32 Go de RAM.
#  {
#    :hostname  => "k3s-node03",
#    :ip        => "192.168.56.44",
#    :box       => BOX_DEBIAN,
#    :version   => BOX_DEBIAN_VERSION,
#    :ram       => 1536,
#    :cpu       => 2,
#    :autostart => false
#  },
]

Vagrant.configure("2") do |config|
  # Les versions etant epinglees, la verification de mise a jour est inutile.
  config.vm.box_check_update = false

  servers.each do |machine|
    config.vm.define machine[:hostname],
                     autostart: machine.fetch(:autostart, true) do |node|
      node.vm.box         = machine[:box]
      node.vm.box_version = machine[:version]
      node.vm.hostname    = machine[:hostname]

      # Reseau host-only : c'est l'adresse utilisee par l'inventaire Ansible.
      # eth0 reste le NAT de VirtualBox (10.0.2.15, identique sur toutes les VMs) ;
      # ne jamais s'y fier — voir le piege k3s du module 15.
      node.vm.network "private_network", ip: machine[:ip]

      # Dossier partage desactive : Ansible travaille en SSH, il n'en a pas besoin.
      # Cela evite aussi la panne classique sur les cibles RHEL-like, ou une mise a
      # jour du noyau desaligne le module vboxsf et fait echouer le `vagrant up`
      # suivant (TP 06 : patching de db01).
      node.vm.synced_folder ".", "/vagrant", disabled: true

      node.vm.provider "virtualbox" do |vb|
        vb.name = machine[:hostname]
        vb.customize ["modifyvm", :id, "--cpus",   machine[:cpu]]
        vb.customize ["modifyvm", :id, "--memory", machine[:ram]]
        # Pas de --firmware efi : la box Rocky 10.1 embarque deja son reglage EFI.
        # VT-x et la pagination imbriquee doivent rester actifs, faute de quoi le
        # jeu d'instructions x86-64-v3 exige par Rocky 10 n'est pas expose.
        vb.customize ["modifyvm", :id, "--nested-paging", "on"]
      end

      # Socle minimal : uniquement l'interpreteur Python attendu par Ansible.
      # Le script est televerse par SSH (pas de dependance au dossier partage).
      node.vm.provision "shell",
        name:       "socle",
        path:       "bootstrap.sh",
        privileged: true
    end
  end
end
