# TP 05 — Du playbook aux rôles

Énoncé : [module 06](../../J1-Socle/06-Roles-Collections.md#tp-05--du-playbook-aux-rôles)

## Contenu

```
site.yml                      3 plays, uniquement des données
requirements.yml              collections et rôles externes
roles/
├── base/                     socle commun (reprise du TP 03)
│   ├── defaults/main.yml
│   ├── tasks/main.yml
│   ├── templates/hosts.j2
│   └── meta/main.yml
├── nginx/                    serveurs web (reprise du TP 04)
│   ├── defaults/main.yml     surchargeable par l'appelant
│   ├── vars/main.yml         chemins imposés par la distribution
│   ├── tasks/main.yml
│   ├── handlers/main.yml
│   ├── templates/
│   └── meta/argument_specs.yml
└── postgres/                 PostgreSQL 16 sur Rocky Linux 10
    ├── defaults/main.yml
    ├── tasks/main.yml
    ├── handlers/main.yml
    └── meta/argument_specs.yml
```

`site.yml` est **à la racine du TP**, pas dans un sous-répertoire : Ansible cherche `roles/`
à côté du playbook.

## Vérification

```bash
I=corrige/tp02-inventaire/inventories/dev/hosts.yml
P=corrige/tp05-roles/site.yml

ansible-galaxy install -r corrige/tp05-roles/requirements.yml
ansible-lint corrige/tp05-roles/
ansible-playbook -i $I $P --list-tasks
ansible-playbook -i $I $P --check --diff
ansible-playbook -i $I $P
ansible-playbook -i $I $P          # idempotence
```

## Ce que le corrigé illustre

| Point | Emplacement |
|---|---|
| `defaults/` surchargeable vs `vars/` imposé | `roles/nginx/defaults` et `roles/nginx/vars` |
| Rôle multi-distribution sans aucun `when: os_family` | `nginx_chemins[ansible_facts['os_family']]` |
| Validation des arguments avant la première tâche | `roles/*/meta/argument_specs.yml` |
| Préfixage des variables par le nom du rôle | partout |
| Commande non idempotente rendue idempotente | `postgresql-setup --initdb` avec `creates` |
| Bascule d'utilisateur pour les opérations SQL | `become_user: postgres` |
| Masquage d'un secret dans la sortie | `no_log: true` |
| Dépendances externes déclarées | `requirements.yml` |

## Détails vérifiés sur Rocky Linux 10

| Élément | Valeur |
|---|---|
| Paquet serveur | `postgresql-server` (PostgreSQL 16) |
| Adaptateur Python | `python3-psycopg2` 2.9.9, présent en AppStream |
| Initialisation | `/usr/bin/postgresql-setup --initdb` |
| Répertoire de données | `/var/lib/pgsql/data` |
| SELinux | enforcing par défaut, d'où `python3-libselinux` |
| firewalld | actif dans la box bento |

## Test de la validation des arguments

```yaml
# Provoque un échec AVANT la première tâche
nginx_sites:
  - nom: mauvais
    log_level: bavard
```

```console
fatal: [web01]: FAILED! => {"argument_errors": [
  "value of log_level must be one of: debug, info, notice, warn, error, crit,
   alert, emerg, got: bavard found in nginx_sites"]}
```
