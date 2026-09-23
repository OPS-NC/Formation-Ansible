# Module 03 — Inventaire et commandes ad hoc

> **Jour 1** · 60 min · Théorie + **TP 02**
> Prérequis : [module 02](02-Noeud-De-Controle.md), lab démarré.

## Objectifs

- Structurer un inventaire YAML en groupes fonctionnels et systèmes.
- Placer les variables au bon endroit et prévoir laquelle l'emporte.
- Cibler un sous-ensemble du parc avec les motifs.
- Utiliser les commandes ad hoc pour auditer et dépanner.

---

## 1. L'inventaire

L'inventaire répond à une question : **quelles machines, et que sait-on d'elles ?**

### 1.1 INI ou YAML

Le format INI reste valide et se rencontre dans le code existant :

```ini
[web]
web01 ansible_host=192.168.56.11
web02 ansible_host=192.168.56.12

[web:vars]
http_port=80
```

Le format YAML est celui à écrire aujourd'hui : il supporte les structures imbriquées (listes,
dictionnaires), impossibles à exprimer en INI.

```yaml
all:
  children:
    web:
      hosts:
        web01:
          ansible_host: 192.168.56.11
        web02:
          ansible_host: 192.168.56.12
      vars:
        http_port: 80
```

> **Attention**
> En YAML, un hôte sans variable s'écrit `web01:` — les deux-points sont obligatoires. `web01`
> seul est interprété comme une chaîne dans une liste et produit une erreur de parsing.

### 1.2 Groupes implicites

Deux groupes existent toujours, sans être déclarés :

- **`all`** : toutes les machines de l'inventaire.
- **`ungrouped`** : les machines n'appartenant à aucun autre groupe.

### 1.3 Deux axes de groupement

Une erreur fréquente consiste à ne grouper que par fonction, puis à multiplier les conditions
dans les tâches :

```yaml
# À éviter
- name: Installer le serveur web
  ansible.builtin.apt:
    name: nginx
  when: ansible_facts['os_family'] == 'Debian'
```

La bonne pratique est de grouper selon **deux axes** et de porter les différences dans des
variables :

| Axe | Groupes | Répond à |
|---|---|---|
| Fonctionnel | `web`, `db`, `ops` | Que fait la machine ? |
| Système | `debian`, `rocky` | Comment lui parle-t-on ? |

Une machine appartient aux deux. Le nom du paquet, le nom du service, l'utilisateur système
deviennent des variables de groupe, et la tâche redevient unique :

> Répéter `web01` dans plusieurs groupes désigne **le même hôte** : une tâche ciblant `all`
> ne sera pas exécutée deux fois sur lui. `inventory_hostname` est son identifiant Ansible ;
> `ansible_host` est son adresse de connexion. Déclarer cet hôte dans `debian` ne détecte pas
> son OS : c'est une information que vous fournissez, à distinguer des facts collectés ensuite.

```yaml
- name: Installer les paquets de base
  ansible.builtin.package:
    name: "{{ paquets_base }}"      # défini dans group_vars/debian.yml et rocky.yml
    state: present
```

Un **groupe de groupes** se déclare avec `children` :

```yaml
    serveurs:
      children:
        web:
        db:
```

> **Attention**
> Ne donnez jamais le même nom à un groupe et à un hôte. Dans le lab, la machine s'appelle
> `tools` et son groupe `ops`, précisément pour cette raison.

## 2. Les variables d'inventaire

### 2.1 Où les écrire

Trois emplacements possibles, par ordre de qualité croissante :

1. **Dans le fichier d'inventaire** (`vars:`) — acceptable pour une poignée de valeurs.
2. **Dans `group_vars/<groupe>.yml` et `host_vars/<hôte>.yml`** — la méthode normale.
3. **Dans un répertoire** `group_vars/<groupe>/` contenant plusieurs fichiers — pour séparer,
   par exemple, `main.yml` et `secrets.yml` (module 11).

Ces répertoires se placent **à côté du fichier d'inventaire** :

```
inventories/
└── dev/
    ├── hosts.yml
    ├── group_vars/
    │   ├── all.yml
    │   ├── web.yml
    │   ├── db.yml
    │   ├── debian.yml
    │   └── rocky.yml
    └── host_vars/
        └── web01.yml
```

> Ils peuvent aussi être placés à côté du **playbook**. Ils sont alors prioritaires sur ceux de
> l'inventaire. Mélanger les deux emplacements est une source classique de confusion : tenez-vous
> à l'inventaire.

### 2.2 Précédence

La documentation officielle liste 22 niveaux. En pratique, six règles suffisent :

| Rang | Source | Remarque |
|---|---|---|
| 1 (plus faible) | `defaults/main.yml` d'un rôle | Prévu pour être surchargé |
| 2 | `group_vars/all` | |
| 3 | `group_vars/<groupe>` | |
| 4 | `host_vars/<hôte>` | L'emporte sur toutes les variables de groupe |
| 5 | `vars:` du play, `set_fact`, `vars/main.yml` d'un rôle | |
| 6 (plus forte) | `-e` / `--extra-vars` | Gagne **toujours** |

Deux conséquences pratiques :

- Une valeur que l'on souhaite pouvoir surcharger va dans `defaults/` d'un rôle.
- Une valeur qui ne doit **pas** l'être va dans `vars/` du rôle.

> Cette table simplifie les priorités, elle ne définit pas des protections : `vars/` gagne
> sur l'inventaire mais reste surchargeable, notamment par `-e`. Une variable comme
> `http_port` est une donnée de votre projet ; elle ne configure rien tant qu'une tâche ou
> un template ne l'utilise pas. À l'inverse, Ansible interprète directement `ansible_user`
> pour choisir le compte SSH.

### 2.3 Deux groupes de même niveau : qui gagne ?

Question posée à chaque formation. `web01` appartient à `web` et à `debian`, et les deux groupes
définissent la même variable. Réponse : **l'ordre alphabétique des noms de groupes**, le dernier
l'emportant. Vérification sur l'inventaire du TP :

```console
$ ansible-playbook -i inventories/dev/hosts.yml precedence.yml
ok: [web01] =>
    msg: groupes=debian,serveurs,web | origine=defini dans group_vars/web.yml
ok: [tools] =>
    msg: groupes=debian,ops | origine=defini dans group_vars/debian.yml
```

`web` l'emporte sur `debian` car « web » vient après « debian ». Pour `tools`, seul `debian`
définit la variable, il n'y a pas d'arbitrage.

Se reposer sur l'alphabet est fragile. Pour fixer l'ordre explicitement, il existe
`ansible_group_priority` : valeur 1 par défaut, la plus élevée l'emporte.

> **Attention**
> `ansible_group_priority` n'a d'effet que dans la section `vars:` du **fichier d'inventaire**.
> Placé dans `group_vars/`, il est lui-même soumis à la fusion qu'il prétend arbitrer, et reste
> sans effet — silencieusement.

Démonstration sur deux groupes `alpha` et `zeta` définissant tous deux la variable `qui`
(sans priorité, `zeta` gagne par ordre alphabétique) :

```yaml
# Cas A — dans le fichier d'inventaire : la priorité s'applique
all:
  children:
    alpha:
      hosts:
        h1:
      vars:
        ansible_group_priority: 10
    zeta:
      hosts:
        h1:
```
```console
resultat -> alpha
```

```yaml
# Cas B — dans group_vars/alpha.yml : la priorité est ignorée
qui: alpha
ansible_group_priority: 10
```
```console
resultat -> zeta
```

La solution robuste reste de **ne pas définir la même variable dans deux groupes du même axe**.

### 2.4 Variables magiques

Fournies par Ansible, toujours disponibles :

| Variable | Contenu |
|---|---|
| `inventory_hostname` | Nom de la machine **dans l'inventaire** |
| `inventory_hostname_short` | Idem, tronqué au premier point |
| `ansible_host` | Adresse réellement utilisée pour se connecter |
| `group_names` | Liste des groupes de la machine courante |
| `groups` | Dictionnaire de tous les groupes et de leurs membres |
| `hostvars` | Accès aux variables des **autres** machines |
| `play_hosts` / `ansible_play_hosts` | Machines encore actives dans le play |
| `inventory_dir` | Répertoire du fichier d'inventaire |

`hostvars` est la clé de toute configuration inter-machines. Exemple : lister les frontaux web
dans la configuration d'un répartiteur de charge.

```yaml
- name: Générer la configuration amont
  ansible.builtin.template:
    src: upstream.conf.j2
    dest: /etc/nginx/conf.d/upstream.conf
```

```jinja
{% for h in groups['web'] %}
server {{ hostvars[h]['ansible_host'] }}:{{ hostvars[h]['http_port'] }};
{% endfor %}
```

> **Attention**
> `hostvars[h]['ansible_facts']` n'est peuplé que si les facts de `h` ont été collectés dans
> **cette exécution**. Si le play ne cible que les répartiteurs, les facts des serveurs web
> n'existent pas. Solutions : un premier play `gather_facts` sur `all`, ou un cache de facts
> (module 08).

## 3. Inspecter un inventaire

`ansible-inventory` lit l'inventaire sans contacter aucune machine. C'est l'outil de diagnostic
à utiliser avant de soupçonner le réseau.

```bash
ansible-inventory --graph                 # arborescence des groupes
ansible-inventory --graph --vars          # avec les variables
ansible-inventory --list                  # tout, en JSON
ansible-inventory --host web01            # variables résolues d'une machine
```

```console
$ ansible-inventory --graph
@all:
  |--@ungrouped:
  |--@web:
  |  |--web01
  |  |--web02
  |--@db:
  |  |--db01
  |--@ops:
  |  |--tools
  |--@debian:
  |  |--web01
  |  |--web02
  |  |--tools
  |--@rocky:
  |  |--db01
  |--@serveurs:
  |  |--@web:
  |  |  |--web01
  |  |  |--web02
  |  |--@db:
  |  |  |--db01
```

## 4. Motifs de ciblage

Le premier argument d'`ansible`, ou la clé `hosts:` d'un play, accepte un motif.

| Motif | Sélection |
|---|---|
| `all` ou `*` | Toutes les machines |
| `web` | Le groupe `web` |
| `web:db` | Union — `web` **ou** `db` |
| `debian:&serveurs` | Intersection — `debian` **et** `serveurs` |
| `serveurs:!web01` | Exclusion — `serveurs` sauf `web01` |
| `~(web\|db)0[12]` | Expression régulière |
| `web[0]` | Premier hôte du groupe |

Résultats vérifiés sur l'inventaire du TP :

```console
all                    -> db01, tools, web01, web02
web:db                 -> db01, web01, web02
serveurs:!web01        -> db01, web02
debian:&serveurs       -> web01, web02
all:!ops               -> db01, web01, web02
```

`--limit` (ou `-l`) restreint un playbook sans le modifier. C'est l'outil de reprise après
incident :

```bash
ansible-playbook site.yml --limit web01
ansible-playbook site.yml --limit '!db01'
ansible-playbook site.yml --limit @/tmp/echecs.txt   # liste d'hôtes dans un fichier
```

> `--list-hosts` affiche les machines qui seraient touchées, sans rien exécuter. À utiliser
> systématiquement avant une opération sur la production.

## 5. Commandes ad hoc

Une commande ad hoc exécute **un seul module** sur un motif, sans playbook.

```
ansible <motif> -m <module> -a "<arguments>" [options]
```

Elles servent à trois choses : **auditer**, **dépanner**, **agir dans l'urgence**. Tout ce qui
est destiné à durer s'écrit dans un playbook.

```bash
# Joignabilité (SSH + Python, pas ICMP)
ansible all -m ansible.builtin.ping

# Facts : tout, puis filtré
ansible web01 -m ansible.builtin.setup
ansible all -m ansible.builtin.setup -a "filter=ansible_distribution*"

# Commande brute
ansible all -a "uptime"                      # le module par défaut est `command`
ansible all -m ansible.builtin.shell -a "df -h / | tail -1"

# Inspection
ansible db01 -m ansible.builtin.service_facts
ansible all -m ansible.builtin.package_facts

# Action nécessitant l'élévation de privilèges
ansible web -m ansible.builtin.package -a "name=htop state=present" --become
```

### `command` ou `shell` ?

| | `ansible.builtin.command` | `ansible.builtin.shell` |
|---|---|---|
| Passe par un shell | Non | Oui |
| Pipes, redirections, `&&`, `$VAR` | Non | Oui |
| Risque d'injection | Faible | Réel |
| À utiliser | Par défaut | Seulement si nécessaire |

Ni l'un ni l'autre n'est idempotent : ils rapportent `changed` à chaque exécution. En playbook,
on les encadre avec `creates`, `removes` ou `changed_when` (module 04).

### `become`

`--become` (ou `-b`) élève les privilèges ; `--become-user` choisit la cible.

```bash
ansible all -m ansible.builtin.command -a "id" --become
ansible db01 -m ansible.builtin.command -a "whoami" --become --become-user postgres
```

Les VMs du lab autorisent `sudo` sans mot de passe. Sur un parc réel, `--ask-become-pass` (`-K`)
demande le mot de passe interactivement.

---

## TP 02 — Inventaire du fil rouge

**Durée : 25 min.** Corrigé : [`corrige/tp02-inventaire/`](../corrige/tp02-inventaire/)

### Objectif

Construire l'inventaire structuré qui servira jusqu'à la fin de la formation, puis auditer le
parc par commandes ad hoc.

### Énoncé

1. **Structurer l'inventaire** `inventories/dev/hosts.yml` :
   - groupes fonctionnels `web` (web01, web02), `db` (db01), `ops` (tools) ;
   - groupes systèmes `debian` (web01, web02, tools) et `rocky` (db01) ;
   - un groupe de groupes `serveurs` réunissant `web` et `db`.

2. **Déplacer les variables de connexion** (`ansible_user`, clé privée) du fichier d'inventaire
   vers `group_vars/all.yml`.

3. **Créer les variables de groupe** :
   - `group_vars/web.yml` : `http_port`, `site_racine` ;
   - `group_vars/db.yml` : `postgresql_port`, `postgresql_base` ;
   - `group_vars/debian.yml` et `group_vars/rocky.yml` : `paquets_base`, `service_ntp`,
     `utilisateur_web`, avec les valeurs propres à chaque famille ;
   - `group_vars/all.yml` : `parc_environnement`, `parc_domaine`, `parc_timezone`.

4. **Créer `host_vars/web01.yml`** avec une variable `banniere` propre à cette machine.

5. **Observer la précédence.** Définir `banniere` dans `all.yml`, `web.yml`, `db.yml` et
   `host_vars/web01.yml`, puis prédire la valeur obtenue par chaque machine **avant** de la
   vérifier :
   ```bash
   ansible all -m ansible.builtin.debug -a "var=banniere"
   ```

6. **Vérifier la structure :**
   ```bash
   ansible-inventory --graph
   ansible-inventory --host web01
   ```

7. **Auditer le parc** par commandes ad hoc, et noter les réponses :
   - version et famille de chaque système ;
   - espace libre sur `/` ;
   - mémoire totale ;
   - présence et version de Python.

8. **Exercer les motifs.** Écrire le motif qui cible :
   - tous les serveurs sauf `web01` ;
   - les machines Debian qui sont aussi des serveurs ;
   - tout sauf le groupe `ops`.
   Vérifier chacun avec `--list-hosts`.

### Résultat attendu

```console
$ ansible all -m ansible.builtin.debug -a "var=banniere"
web01 | SUCCESS =>
    banniere: web01 - frontal principal
web02 | SUCCESS =>
    banniere: Serveur web - lab formation
db01 | SUCCESS =>
    banniere: Serveur de base de donnees - lab formation
tools | SUCCESS =>
    banniere: Machine du lab - usage formation
```

L'ordre des machines varie d'une exécution à l'autre : les quatre hôtes sont traités en
parallèle (`forks = 10`), et chacun s'affiche dès qu'il répond.

### Pièges courants

| Symptôme | Cause |
|---|---|
| `group_vars` ignorés | Répertoire placé ailleurs qu'à côté du fichier d'inventaire |
| `Unable to parse ... as an inventory source` | `web01` écrit sans les deux-points en YAML |
| Variable inattendue | Deux groupes du même axe définissent la même clé |
| `skipping: no hosts matched` | Motif erroné — contrôler avec `--list-hosts` |

### Pour aller plus loin

- Écrire le même inventaire au format INI et mesurer ce qui devient impossible à exprimer.
- Afficher, depuis `web01`, l'adresse de `db01` avec
  `ansible web01 -m ansible.builtin.debug -a "msg={{ hostvars['db01']['ansible_host'] }}"`.

---

## Points clés

- **Deux axes de groupement** : fonction et système. Les différences deviennent des variables,
  pas des conditions.
- Les variables vivent dans **`group_vars/` et `host_vars/`, à côté de l'inventaire**.
- `host_vars` l'emporte sur `group_vars` ; `-e` l'emporte sur tout.
- Entre deux groupes de même niveau, c'est **l'ordre alphabétique** qui tranche — ne comptez
  pas dessus.
- **`ansible-inventory` ne contacte aucune machine** : c'est le premier outil de diagnostic.
- Les commandes ad hoc servent à auditer et dépanner, pas à configurer durablement.

---

**Module précédent :** [02 — Nœud de contrôle et lab](02-Noeud-De-Controle.md)
**Module suivant :** [04 — Playbooks : fondamentaux](04-Playbooks.md)
