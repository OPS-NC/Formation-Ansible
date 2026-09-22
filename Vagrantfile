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
BOX_VYOS           = "vyos/current"
BOX_VYOS_VERSION   = "20240817.00.20"   # figee depuis aout 2024, suffisante pour le TP

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
  # --- Lab jour 3 : equipement reseau ---------------------------------------
  # VyOS est un routeur logiciel pilotable par la collection vyos.vyos et la
  # connexion network_cli. C'est la seule pile reseau libre qui fonctionne sous
  # VirtualBox sans Docker, sans compte et sans licence.
  #
  # `bootstrap` est desactive : VyOS n'est pas un Debian ordinaire, sa
  # configuration passe par son propre systeme, pas par apt.
  {
    :hostname  => "net01",
    :ip        => "192.168.56.51",
    # Seconde carte : le TP configure deux interfaces (eth1 et eth2).
    # Sans elle, eth2 n'existe pas et la configuration est rejetee.
    #
    # L'adresse DOIT rester dans 192.168.56.0/21, seule plage host-only
    # autorisee par defaut depuis VirtualBox 6.1.28. Une adresse hors plage
    # (10.10.20.1, par exemple) fait echouer `vagrant up net01` :
    #   The IP address configured for the host-only network is not within the
    #   allowed ranges.
    #     Address: 10.10.20.1
    #     Ranges: 192.168.56.0/21, fe80::/10
    # La contourner imposerait de creer /etc/vbox/networks.conf, que le
    # module 02 annonce explicitement comme inutile.
    :ip2       => "192.168.60.1",
    :box       => BOX_VYOS,
    :version   => BOX_VYOS_VERSION,
    :ram       => 1024,
    :cpu       => 1,
    :autostart => false,
    :bootstrap => false
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

      # VyOS n'est pas un invite reconnu par Vagrant : aucun greffon ne sait y
      # regler le nom d'hote ni configurer une interface. Le lui demander fait
      # echouer `vagrant up` en fin de demarrage, machine deja lancee :
      #   The guest operating system of the machine could not be detected!
      # On lui laisse donc son nom d'hote et on configure ses interfaces par
      # son propre systeme (voir le provisionnement plus bas).
      invite_reconnu = machine.fetch(:bootstrap, true)

      node.vm.hostname = machine[:hostname] if invite_reconnu

      # Le remplacement automatique de la cle SSH est DESACTIVE sur VyOS.
      # VyOS regenere ~/.ssh/authorized_keys depuis son propre systeme de
      # configuration a chaque demarrage : la cle inseree par Vagrant est
      # perdue au premier redemarrage, et `vagrant reload net01` echoue sur
      #   vyos@127.0.0.1: Permission denied (publickey,password).
      # La box embarque la cle Vagrant publique dans sa configuration : c'est
      # elle qu'on utilise, et l'inventaire du TP 13 la designe.
      node.ssh.insert_key = false unless invite_reconnu

      # VyOS n'est pas auto-detecte par Vagrant. Sans cette declaration,
      # `vagrant up` echoue APRES le demarrage de la machine :
      #   The guest operating system of the machine could not be detected!
      # La cause n'est pas le dossier partage, pourtant desactive ci-dessous :
      # l'action synced_folders de Vagrant 2.4.9 interroge malgre tout
      # l'invite (capability?(:persist_mount_shared_folder)) et ne rattrape
      # pas l'echec de detection.
      #
      # VyOS est un Debian : le declarer comme tel court-circuite la
      # detection. Les capacites Debian qui seraient inadaptees ne sont jamais
      # sollicitees, puisque le nom d'hote et l'adressage des interfaces sont
      # tous deux desactives juste au-dessus.
      node.vm.guest = :debian unless invite_reconnu

      # Reseau host-only : c'est l'adresse utilisee par l'inventaire Ansible.
      # eth0 reste le NAT de VirtualBox (10.0.2.15, identique sur toutes les VMs) ;
      # ne jamais s'y fier — voir le piege k3s du module 15.
      #
      # `auto_config: false` sur VyOS : la carte est bien attachee par
      # VirtualBox, mais Vagrant n'essaie pas de l'adresser dans l'invite.
      node.vm.network "private_network",
                      ip: machine[:ip],
                      auto_config: invite_reconnu

      # Certaines machines ont une seconde carte sur un reseau applicatif.
      if machine[:ip2]
        node.vm.network "private_network",
                        ip: machine[:ip2],
                        auto_config: invite_reconnu
      end

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
      # Les equipements reseau en sont exemptes.
      if invite_reconnu
        node.vm.provision "shell",
          name:       "socle",
          path:       "bootstrap.sh",
          privileged: true
      else
        # VyOS : on donne a eth1 l'adresse attendue par l'inventaire du TP 13,
        # sans quoi l'equipement n'est joignable que par le NAT.
        # `privileged: false` : la configuration VyOS se fait sous le compte
        # `vyos`, JAMAIS en root. Un `configure`/`commit`/`save` lance par
        # root laisse le systeme de configuration dans un etat ou toute
        # commande ulterieure de l'utilisateur `vyos` echoue sur un laconique
        #   Set failed
        # ce qui rend le TP 13 impraticable.
        node.vm.provision "shell",
          name:       "socle reseau",
          path:       "bootstrap-vyos.sh",
          args:       [machine[:ip]],
          privileged: false
      end
    end
  end
end
