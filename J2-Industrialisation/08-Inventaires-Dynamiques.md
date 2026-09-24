# Module 08 — Inventaires dynamiques et cache de facts

> **Jour 2** · 45 min · Théorie + **TP 07**
> Prérequis : [module 07](07-Execution-Avancee.md).

## 🎯 Objectifs

- Remplacer un inventaire statique par une source de vérité.
- Enrichir un inventaire existant avec le greffon `constructed`.
- Activer un cache de facts et en comprendre les effets.

---

## 1. Pourquoi

Un inventaire statique décrit le parc **tel qu'il était** le jour où quelqu'un l'a écrit. Dès que
les machines sont créées et détruites par une plateforme — cloud, Proxmox, vSphere, Kubernetes —
il diverge. L'inventaire dynamique interroge la plateforme à chaque exécution.

## 2. Les greffons d'inventaire

Un greffon (*plugin*) d'inventaire est un composant qui **produit** un inventaire. Les greffons
autorisés sont listés dans `ansible.cfg` :

```ini
[inventory]
enable_plugins = host_list, script, auto, yaml, ini, toml, constructed
```

`auto` détecte le bon greffon à partir de la clé `plugin:` du fichier. C'est le mécanisme
habituel : un fichier `*.yml` contenant `plugin: community.proxmox.proxmox` est traité par ce
greffon.

| Greffon | Source |
|---|---|
| `ansible.builtin.yaml`, `.ini` | Fichier statique |
| `ansible.builtin.constructed` | Enrichit un inventaire existant |
| `community.proxmox.proxmox` | API Proxmox VE (module 13) |
| `vmware.vmware.vms` | vCenter (module 13) |
| `amazon.aws.aws_ec2` | AWS |
| `netbox.netbox.nb_inventory` | NetBox (module 14) |
| `cloud.terraform.terraform_state` | État Terraform / OpenTofu |
| `community.libvirt.libvirt` | KVM local |

### Plusieurs sources à la fois

`-i` accepte un **répertoire** : toutes les sources qu'il contient sont fusionnées, dans l'ordre
**alphabétique** des noms de fichiers.

```
inventories/dev/
├── 01-hosts.yml          machines statiques
├── 02-constructed.yml    enrichissement
├── group_vars/
└── host_vars/
```

> Le préfixe numérique n'est pas cosmétique : `constructed` ne peut enrichir que des machines
> **déjà** déclarées. S'il est lu en premier, il n'a rien à traiter.

## 3. Le greffon `constructed`

Il ne déclare aucune machine : il ajoute des groupes et des variables à celles qui existent.

```yaml
plugin: ansible.builtin.constructed
strict: false

compose:
  fqdn: inventory_hostname ~ '.' ~ parc_domaine

keyed_groups:
  - key: parc_environnement
    prefix: env
    separator: "_"
  - key: rang_maintenance | default('standard')
    prefix: rang
    separator: "_"

groups:
  frontaux: "'web' in group_names"
  petite_memoire: "ansible_memtotal_mb | default(9999) | int < 1500"
```

| Clé | Rôle |
|---|---|
| `compose` | Crée des variables calculées |
| `keyed_groups` | Un groupe par **valeur** distincte d'une variable |
| `groups` | Un groupe par **condition** booléenne |
| `strict` | `false` : ignore une expression dont la variable est absente |

Résultat sur l'inventaire du fil rouge :

```console
$ ansible-inventory -i inventories/dev/ --graph
...
  |--@frontaux:
  |  |--web01
  |  |--web02
  |--@env_dev:
  |  |--web01
  |  |--web02
  |  |--db01
  |  |--tools
  |--@rang_canari:
  |  |--web01
  |--@rang_standard:
  |  |--web02
  |  |--db01
  |  |--tools
```

Ces groupes alimentent directement `serial` (module 07) : on met à jour `rang_canari` avant
`rang_standard`.

### 🪤 Deux pièges vérifiés

> **Attention — `group_vars/` est invisible pour un greffon d'inventaire**
> Les greffons s'exécutent **avant** le chargement de `group_vars/` et `host_vars/`. Une variable
> qui n'existe que dans ces répertoires ne peut pas servir de clé à `keyed_groups`.
>
> Démonstration : avec `parc_environnement` dans `group_vars/all.yml`, aucun groupe `env_*` n'est
> créé. Déplacée dans la section `vars:` du fichier d'inventaire, elle produit immédiatement
> `env_dev`. Même constat pour une variable d'hôte : `rang_maintenance` dans
> `host_vars/web01.yml` ne donne rien ; écrite directement sur la machine dans l'inventaire, elle
> produit `rang_canari`.
>
> 📌 **Règle : toute variable servant à construire l'inventaire se déclare dans la source
> d'inventaire.**

> **Attention — les facts en cache sont exposés à plat**
> Dans un greffon d'inventaire, un fact mis en cache s'écrit `ansible_distribution`, **pas**
> `ansible_facts['distribution']`. Le dictionnaire `ansible_facts` n'est reconstitué qu'au moment
> du play.
>
> Vérification sur une même machine, avec cache actif :
> ```yaml
> keyed_groups:
>   - key: ansible_system | default('X')          # → groupe osv_Darwin
>     prefix: osv
>   - key: ansible_facts['system'] | default('Y') # → groupe osf_Y  (valeur par défaut)
>     prefix: osf
> ```
> Seule la première forme fonctionne.

## 4. 💾 Le cache de facts

Sans cache, les facts sont recollectés à chaque exécution, et n'existent pas au moment où
l'inventaire est construit.

```ini
[defaults]
fact_caching            = jsonfile
fact_caching_connection = ./facts_cache
fact_caching_timeout    = 7200
gathering               = smart
```

| Greffon de cache | Usage |
|---|---|
| `memory` (défaut) | Durée de vie de l'exécution uniquement |
| `jsonfile` | Fichiers locaux — simple, adapté à un poste ou à un runner |
| `redis`, `memcached` | Partagé entre plusieurs contrôleurs |

`gathering = smart` ne collecte que si le cache est vide ou périmé.

Trois bénéfices :

1. **Vitesse** — la collecte est souvent le poste le plus coûteux d'un playbook court.
2. **Groupes construits à partir de facts** — sans cache, `os_*` reste indéterminé.
3. **`hostvars` complet** — on peut lire les facts d'une machine absente du play courant.

```bash
ansible all -m ansible.builtin.setup      # alimente le cache
ansible-inventory --graph                 # les groupes issus des facts apparaissent
rm -rf ./facts_cache                      # purge
```

> **Attention**
> Un cache périmé fait raisonner sur un parc qui n'existe plus. Réglez `fact_caching_timeout`
> en fonction du rythme de changement, et purgez-le avant toute décision critique.

## 5. Écrire ou générer un inventaire

Avant d'écrire un greffon, vérifiez qu'il n'existe pas : la plupart des plateformes sont
couvertes. Si votre source de vérité est un outil interne, deux voies :

- **Un greffon d'inventaire** — la bonne solution, réutilisable et compatible avec le cache.
- **Un script** retournant du JSON (`ansible.builtin.script`) — plus rapide à écrire, mais sans
  cache ni options ; à réserver au dépannage.

Dans tous les cas, `ansible-inventory --list` valide le résultat sans exécuter quoi que ce soit.

---

## TP 07 — Inventaire construit et cache de facts

**Durée : 20 min.** Corrigé : [`corrige/tp07-inventaire-dynamique/`](../corrige/tp07-inventaire-dynamique/)

### Objectif

Enrichir l'inventaire du fil rouge avec des groupes calculés, et activer un cache de facts.

> **Ordre des opérations.** Ansible construit l'inventaire avant de lancer les tâches.
> La collecte `setup` remplit le cache ; c'est à la lecture suivante de l'inventaire que
> `constructed` peut en tirer de nouveaux groupes. Ces groupes sélectionnent des hôtes,
> mais ne définissent aucun ordre d'exécution : les deux appels de patching de l'étape 5
> imposent explicitement « canari, puis reste du parc ».
>
> Après le renommage de `hosts.yml`, réglez aussi `inventory = inventories/dev/` dans
> `ansible.cfg`, ou passez ce répertoire avec `-i` à chaque commande. Sinon les commandes
> sans `-i` continuent de chercher l'ancien fichier.

### Énoncé

1. **Réorganiser l'inventaire en répertoire** : renommer le fichier statique `01-hosts.yml` et
   ajouter `02-constructed.yml`. Vérifier que `-i inventories/dev/` charge bien les deux.

2. **Écrire l'inventaire construit** :
   - `compose` : une variable `fqdn` et une variable `memoire_go` calculée depuis les facts ;
   - `keyed_groups` : un groupe par environnement, par distribution, et par rang de maintenance
     (valeur par défaut `standard`) ;
   - `groups` : `frontaux`, `bases_de_donnees`, `a_redemarrer_en_dernier`, `petite_memoire`.

3. **Déclarer `rang_maintenance: canari` sur `web01`** et `parc_environnement` de façon à ce que
   les groupes `rang_*` et `env_*` soient réellement créés. Vérifier l'effet de l'emplacement de
   la déclaration.

4. **Activer le cache de facts** dans un `ansible.cfg`, puis :
   ```bash
   ansible-inventory --graph          # os_inconnu : pas de facts
   ansible all -m ansible.builtin.setup
   ansible-inventory --graph          # os_Debian et os_Rocky apparaissent
   ```

5. **Utiliser les nouveaux groupes** : relancer le patching du TP 06 en traitant d'abord
   `rang_canari`, puis le reste.
   ```bash
   ansible-playbook playbooks/patching.yml --limit rang_canari
   ansible-playbook playbooks/patching.yml --limit 'serveurs:!rang_canari'
   ```

### Points d'attention

- Le préfixe numérique des fichiers impose l'ordre de lecture. `constructed` doit passer en
  second.
- Une variable définie dans `group_vars/` **n'est pas visible** du greffon. C'est l'objet de
  l'étape 3.
- Un fact en cache s'écrit `ansible_distribution`, pas `ansible_facts['distribution']`.
- `strict: false` évite qu'une variable absente ne fasse échouer tout l'inventaire.

### ⚠️ Pièges courants

| Symptôme | Cause |
|---|---|
| Aucun groupe créé | `constructed` lu avant la source statique |
| `env_*` absent | Variable déclarée dans `group_vars/` |
| `os_inconnu` persistant | Cache de facts vide ou non configuré |
| Groupe vide alors que le fact existe | `ansible_facts['x']` au lieu de `ansible_x` |
| L'inventaire entier échoue | `strict: true` avec une variable absente |

### 🚀 Pour aller plus loin

- Ajouter un `keyed_groups` sur `ansible_processor_vcpus` et cibler les machines à 1 vCPU.
- Comparer la durée d'un playbook court avec et sans cache, callback `timer` activé.
- Lire `ansible-inventory --list --yaml` et retrouver les variables produites par `compose`.

---

## 🔑 Points clés

- `-i` accepte un **répertoire** ; les sources sont fusionnées par ordre alphabétique.
- `constructed` **enrichit**, il ne déclare pas : il doit être lu en second.
- **`group_vars/` et `host_vars/` sont invisibles pour un greffon d'inventaire.**
- **Les facts en cache sont exposés à plat** : `ansible_distribution`.
- Le cache de facts conditionne les groupes construits à partir de facts.
- `ansible-inventory --graph` et `--list` valident sans contacter les machines.

---

**Module précédent :** [07 — Exécution avancée](07-Execution-Avancee.md)
**Module suivant :** [09 — Qualité : lint et tests](09-Qualite.md)
