# TP 12 — Provisionner sans infrastructure

Énoncé : [module 13](../../J3-Perimetres-Avances/13-Provisioning.md#tp-12--provisionner-sans-infrastructure)

## Contenu

```
proxmox/
├── creer-vm.yml              clonage de gabarit, cloud-init, démarrage, attente SSH
└── inventory.proxmox.yml     inventaire dynamique, groupes issus des tags
vmware/
├── deployer-vm.yml           déploiement depuis un gabarit vSphere
└── inventory.vmware.yml      inventaire dynamique vSphere
```

## Vérification

Ce TP se valide **sans infrastructure** :

```bash
ansible-playbook corrige/tp12-provisioning/proxmox/creer-vm.yml --syntax-check
ansible-playbook corrige/tp12-provisioning/vmware/deployer-vm.yml --syntax-check
ansible-lint corrige/tp12-provisioning/
```

Pour une exécution réelle, fournissez les secrets par l'environnement :

```bash
export PROXMOX_HOST=pve.lab.local
export PROXMOX_USER=ansible@pve
export PROXMOX_TOKEN_ID=automation
export PROXMOX_TOKEN_SECRET=...
ansible-playbook corrige/tp12-provisioning/proxmox/creer-vm.yml
```

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
| Nom du fichier d'inventaire | doit finir par `.proxmox.yml` |
| `vmware.vmware` | 2.10.0 |
| `community.vmware.vmware_vm_inventory` | déprécié, retrait en 7.0.0 |

> Aucune infrastructure Proxmox ou vSphere n'était disponible lors de la rédaction. Le code
> passe `--syntax-check` et `ansible-lint` au profil production ; les noms de modules et
> d'options ont été contrôlés un à un avec `ansible-doc`.
