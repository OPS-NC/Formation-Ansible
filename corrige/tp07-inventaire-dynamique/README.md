# TP 07 — Inventaire construit et cache de facts

Énoncé : [module 08](../../J2-Industrialisation/08-Inventaires-Dynamiques.md#tp-07--inventaire-construit-et-cache-de-facts)

## Contenu

```
ansible.cfg                      active le cache de facts jsonfile
inventories/dev/
├── 01-hosts.yml                 machines (variables de construction déclarées ici)
├── 02-constructed.yml           groupes et variables calculés
├── group_vars/                  variables de play (invisibles du greffon)
└── host_vars/
```

## Vérification

```bash
D=corrige/tp07-inventaire-dynamique

ansible-inventory -i $D/inventories/dev/ --graph
ansible-inventory -i $D/inventories/dev/ --host web01

# Avec cache de facts
ANSIBLE_CONFIG=$D/ansible.cfg ansible -i $D/inventories/dev/ all -m ansible.builtin.setup
ANSIBLE_CONFIG=$D/ansible.cfg ansible-inventory -i $D/inventories/dev/ --graph
```

## Groupes produits sans cache de facts

```
|--@frontaux:           web01, web02
|--@bases_de_donnees:   db01
|--@a_redemarrer_en_dernier: db01, tools
|--@env_dev:            web01, web02, db01, tools
|--@os_inconnu:         web01, web02, db01, tools     <- facts absents
|--@rang_canari:        web01
|--@rang_standard:      web02, db01, tools
```

Après `ansible all -m setup`, `os_inconnu` est remplacé par `os_Debian` et `os_Rocky`.

## Les deux pièges démontrés par ce corrigé

### 1. `group_vars/` est invisible pour le greffon

`parc_environnement` et `rang_maintenance` sont déclarés **dans `01-hosts.yml`**, pas dans
`group_vars/` ni `host_vars/`. Déplacez-les dans ces répertoires et les groupes `env_*` et
`rang_*` disparaissent : les greffons d'inventaire s'exécutent avant leur chargement.

### 2. Les facts en cache sont exposés à plat

| Écriture | Dans un greffon d'inventaire |
|---|---|
| `ansible_distribution` | Fonctionne |
| `ansible_facts['distribution']` | Toujours indéfini |

Le dictionnaire `ansible_facts` n'est reconstitué qu'au moment du play.

## Utilisation avec le TP 06

L'inventaire de ce TP ne contient pas les variables de patching du TP 06 :
il faut donc charger les deux repertoires.

```bash
I1=corrige/tp07-inventaire-dynamique/inventories/dev/
I2=corrige/tp06-patching/inventories/dev/
P=corrige/tp06-patching/playbooks/patching.yml

ansible-playbook -i $I1 -i $I2 $P --limit rang_canari
ansible-playbook -i $I1 -i $I2 $P --limit 'serveurs:!rang_canari'
```
