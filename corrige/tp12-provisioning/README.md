# TP 12 — Provisionner sans infrastructure

Énoncé : [module 13](../../J3-Perimetres-Avances/13-Provisioning.md#tp-12--provisionner-sans-infrastructure)

## Contenu

```
proxmox/
├── creer-vm.yml              clonage de gabarit, cloud-init, démarrage, attente SSH
└── inventory.proxmox.yml     inventaire dynamique, groupes issus des tags
vmware/
├── deployer-vm.yml           déploiement depuis un gabarit vSphere
└── inventory.vmware_vms.yml  inventaire dynamique vSphere
```

## Vérification

Ce TP se valide **sans infrastructure** :

```bash
ansible-playbook corrige/tp12-provisioning/proxmox/creer-vm.yml --syntax-check
ansible-playbook corrige/tp12-provisioning/vmware/deployer-vm.yml --syntax-check
ansible-lint corrige/tp12-provisioning/
```

### Bibliothèques Python

Une collection Galaxy **n'installe pas** ses dépendances Python. Elles vivent dans
l'environnement virtuel d'Ansible, `pip install` étant refusé sur Ubuntu 26.04 (PEP 668,
module 02) :

```bash
pipx inject ansible proxmoxer requests     # community.proxmox
pipx inject ansible pyvmomi aiohttp        # vmware.vmware
```

Sans elles, le greffon d'inventaire est bien sélectionné mais échoue immédiatement :

```
[WARNING]: Failed to parse inventory with 'auto' plugin: This module requires
Python Requests 1.1.0 or higher
[WARNING]: Failed to parse inventory with 'auto' plugin: Failed to import the
required Python library (pyvmomi)
```

### Exécution réelle

Pour une exécution réelle, fournissez les secrets par l'environnement :

```bash
export PROXMOX_HOST=pve.lab.local
export PROXMOX_USER=ansible@pve
export PROXMOX_TOKEN_ID=automation
export PROXMOX_TOKEN_SECRET=...

# L'inventaire dynamique doit etre passe en -i : `meta: refresh_inventory`
# recharge les sources DEJA selectionnees, il n'en decouvre aucune.
ansible-playbook \
  -i corrige/tp12-provisioning/proxmox/inventory.proxmox.yml \
  corrige/tp12-provisioning/proxmox/creer-vm.yml
```

> Le second play cible le groupe `tag_dev`, construit par l'inventaire à partir
> des tags Proxmox posés lors de la création. Sans le `-i`, ce groupe n'existe
> pas et le play ne s'applique à aucune machine.

L'assertion en début de playbook échoue explicitement si le secret est absent, plutôt que de
laisser l'API renvoyer une erreur d'authentification obscure.

## Ce que le corrigé illustre

| Point | Emplacement |
|---|---|
| Les modules d'API s'exécutent sur le contrôleur | `hosts: localhost`, `connection: local` |
| Authentification par jeton révocable | `api_token_id` / `api_token_secret` |
| Échec explicite si le secret manque | tâche `assert` initiale |
| Machines décrites comme données | variable `machines` |
| Amorçage sans connexion préalable | `ciuser`, `sshkeys`, `ipconfig` |
| Enchaînement création → configuration | `meta: refresh_inventory` |
| Tags de l'hyperviseur devenus groupes | `keyed_groups` sur `proxmox_tags_parsed` |
| Collection VMware à jour | `vmware.vmware`, et non `community.vmware` |

## Détails vérifiés

| Élément | Valeur |
|---|---|
| `community.proxmox` | 2.0.0, `validate_certs` à `true` par défaut |
| États de `proxmox_kvm` | present, started, stopped, restarted, absent, template, paused, hibernated |
| Nom du fichier d'inventaire Proxmox | doit finir par `.proxmox.yml` ou `.proxmox.yaml` |
| Nom du fichier d'inventaire vSphere | doit finir par `vms.yml`, `vms.yaml`, `vmware_vms.yml` ou `vmware_vms.yaml` — **pas** la même convention que Proxmox |
| `vmware.vmware` | 2.10.0 |
| `community.vmware.vmware_vm_inventory` | déprécié, retrait en 7.0.0 |

> Aucune infrastructure Proxmox ou vSphere n'était disponible lors de la validation. Ce qui a
> pu être vérifié sans elle, au-delà de `--syntax-check` et d'`ansible-lint` :
>
> - l'assertion d'entrée échoue bien, avec son message explicite, quand le secret manque ;
> - les deux greffons d'inventaire sont **chargés et configurés** — ils vont jusqu'à la
>   tentative de connexion réseau, qui est le dernier point atteignable sans hyperviseur :
>
> ```
> HTTPSConnectionPool(host='pve.lab.local', port=8006): ... Failed to resolve 'pve.lab.local'
> Unknown error while connecting to the vCenter or ESXi API at vcenter.lab.local:443
> ```
>
> Ce qui reste non vérifié : la création réelle d'une VM, les tags remontés en groupes, et
> l'enchaînement `meta: refresh_inventory`.
