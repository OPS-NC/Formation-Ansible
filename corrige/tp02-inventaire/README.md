# TP 02 — Inventaire du fil rouge

Énoncé : [module 03](../../J1-Socle/03-Inventaire.md#tp-02--inventaire-du-fil-rouge)

## Contenu

```
inventories/dev/
├── hosts.yml              4 machines, 2 axes de groupement, 1 groupe de groupes
├── group_vars/
│   ├── all.yml            connexion SSH, identite du parc
│   ├── web.yml            http_port, site_racine
│   ├── db.yml             postgresql_port, postgresql_base
│   ├── debian.yml         paquets, service NTP, utilisateur web (famille Debian)
│   └── rocky.yml          idem pour la famille RHEL
└── host_vars/
    └── web01.yml          surcharge propre a web01
```

## Vérification

Depuis la racine du dépôt :

```bash
I=corrige/tp02-inventaire/inventories/dev/hosts.yml
ansible-inventory -i $I --graph
ansible-inventory -i $I --host web01
ansible -i $I all -m ansible.builtin.debug -a "var=banniere"
```

## Précédence attendue sur `banniere`

| Machine | Valeur retenue | Source |
|---|---|---|
| `web01` | `web01 - frontal principal` | `host_vars/web01.yml` |
| `web02` | `Serveur web - lab formation` | `group_vars/web.yml` |
| `db01` | `Serveur de base de donnees - lab formation` | `group_vars/db.yml` |
| `tools` | `Machine du lab - usage formation` | `group_vars/all.yml` |

## Motifs de ciblage vérifiés

```
all                    -> db01, tools, web01, web02
web:db                 -> db01, web01, web02
serveurs:!web01        -> db01, web02
debian:&serveurs       -> web01, web02
all:!ops               -> db01, web01, web02
```
