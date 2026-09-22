# TP 01 — Mise en place du lab

Énoncé : [module 02](../../J1-Socle/02-Noeud-De-Controle.md#tp-01--mise-en-place-du-lab)

## Contenu

| Fichier | Rôle |
|---|---|
| `inventories/dev/hosts.yml` | Inventaire minimal des 4 VMs du jour 1 |

Le fichier `ansible.cfg` du TP se trouve à la **racine du dépôt** : c'est le répertoire
courant qui détermine le fichier de configuration chargé.

## Vérification

Depuis la racine du dépôt :

```bash
ansible-inventory -i corrige/tp01-lab/inventories/dev/hosts.yml --graph
ansible -i corrige/tp01-lab/inventories/dev/hosts.yml all -m ansible.builtin.ping
```

Résultat attendu du premier appel :

```
@all:
  |--@ungrouped:
  |  |--web01
  |  |--web02
  |  |--db01
  |  |--tools
```
