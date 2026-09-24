# Module 06 — Rôles, collections et réutilisation

> **Jour 1** · 75 min · Théorie + **TP 05**
> Prérequis : [module 05](05-Variables-Jinja-Handlers.md).

## 🎯 Objectifs

- Transformer un playbook en rôle réutilisable et paramétrable.
- Distinguer `defaults/` et `vars/`, et valider les arguments d'un rôle.
- Comprendre ce qu'est une collection et déclarer ses dépendances.
- Évaluer un contenu Galaxy avant de l'adopter.

---

## 1. Du playbook au rôle

Le playbook du TP 04 fonctionne, mais il n'est pas réutilisable : sa logique et ses données sont
dans le même fichier. Un rôle sépare les deux.

```
roles/nginx/
├── defaults/main.yml       variables surchargeables (précédence faible)
├── vars/main.yml           variables internes (précédence forte)
├── tasks/main.yml          les tâches
├── handlers/main.yml       les handlers
├── templates/              gabarits Jinja2
├── files/                  fichiers transférés tels quels
├── meta/main.yml           métadonnées, dépendances
└── meta/argument_specs.yml validation des arguments
```

Les répertoires inutiles sont simplement omis. `ansible-galaxy init <nom>` crée le squelette
complet, `ansible-creator init role` une version plus moderne — mais l'écrire à la main reste
formateur.

### `defaults/` ou `vars/` ?

C'est la décision structurante d'un rôle.

| | `defaults/main.yml` | `vars/main.yml` |
|---|---|---|
| Précédence | La **plus faible** de toutes | Élevée |
| Surchargeable par l'inventaire | Oui | Non, en pratique |
| Contenu | Ce que l'appelant **doit** pouvoir régler | Ce qu'il ne doit **pas** toucher |
| Exemple | port, liste des sites, chemins fonctionnels | chemins imposés par la distribution |

```yaml
# defaults/main.yml — l'appelant décide
nginx_sites: []
nginx_port_defaut: 80
nginx_site_racine: /var/www/formation
```

```yaml
# vars/main.yml — l'empaquetage décide, pas l'utilisateur
nginx_chemins:
  Debian:
    disponibles: /etc/nginx/sites-available
    actives: /etc/nginx/sites-enabled
    utilisateur: www-data
  RedHat:
    disponibles: /etc/nginx/conf.d
    actives: /etc/nginx/conf.d
    utilisateur: nginx
```

```yaml
# tasks/main.yml — une seule ligne remplace tous les `when: os_family == ...`
- name: Selectionner les chemins propres a la distribution
  ansible.builtin.set_fact:
    nginx_conf: "{{ nginx_chemins[ansible_facts['os_family']] }}"
```

### Préfixer les variables

Toutes les variables d'un rôle sont préfixées par son nom : `nginx_port_defaut`, pas `port`.
Les variables de rôle vivent dans le même espace de noms global que toutes les autres : sans
préfixe, deux rôles finissent par se marcher dessus. `ansible-lint` le vérifie avec la règle
`var-naming[no-role-prefix]`.

## 2. Valider les arguments

Sans validation, une faute de frappe dans un nom de variable ne se manifeste que plus tard —
parfois plusieurs tâches après, sous une forme incompréhensible. `meta/argument_specs.yml`
déplace l'erreur **avant la première tâche**. Disponible depuis `ansible-core` 2.11.

```yaml
argument_specs:
  main:
    short_description: Deploiement de sites nginx
    options:
      nginx_sites:
        type: list
        elements: dict
        required: true
        description: Liste des sites a deployer.
        options:
          nom:
            type: str
            required: true
            description: Identifiant du site.
          log_level:
            type: str
            default: warn
            choices: [debug, info, notice, warn, error, crit, alert, emerg]
            description: Niveau de journalisation.
```

Effet immédiat sur une valeur invalide :

```console
$ ansible-playbook site.yml
TASK [nginx : Validating arguments against arg spec 'main'] *********************
fatal: [web01]: FAILED! => {
  "argument_errors": [
    "value of log_level must be one of: debug, info, notice, warn, error, crit,
     alert, emerg, got: bavard found in nginx_sites"
  ]
}
```

La tâche de validation est ajoutée automatiquement, porte le tag `always`, et apparaît dans
`--list-tasks`. `ansible-doc -t role formation.nginx` exploite le même fichier pour documenter
le rôle.

## 3. Appeler un rôle

| Forme | Moment | Usage |
|---|---|---|
| `roles:` dans le play | Statique, **avant** les `tasks:` | Cas courant |
| `ansible.builtin.import_role` | Statique, à la position voulue | Ordonner précisément |
| `ansible.builtin.include_role` | **Dynamique**, à l'exécution | Rôle choisi par une variable ou une boucle |

```yaml
- name: Deploiement des serveurs web
  hosts: web
  become: true
  roles:
    - role: nginx
      nginx_site_racine: "{{ site_racine }}"
      nginx_sites:
        - nom: vitrine
        - nom: api
          port: 8080
```

Différence pratique : un rôle **importé** voit ses tâches connues dès l'analyse, donc `--list-tasks`
et `--start-at-task` fonctionnent, et les tags se propagent. Un rôle **inclus** n'est résolu qu'à
l'exécution : il peut être choisi dynamiquement, mais `--list-tasks` ne le voit pas et les tags
doivent être appliqués avec `apply:`.

### Chemin de recherche

Ansible cherche un rôle dans, par ordre :

1. `roles/` **à côté du playbook** ;
2. les chemins de `roles_path` (`ansible.cfg`) ;
3. `~/.ansible/roles`, `/usr/share/ansible/roles`, `/etc/ansible/roles`.

> **Attention**
> C'est le répertoire du **playbook** qui compte, pas la racine du projet. Un playbook rangé dans
> `playbooks/` ne trouvera pas `roles/` situé à la racine, sauf à renseigner `roles_path`.
> Erreur type : `the role 'base' was not found in: .../playbooks/roles:...`.
> Deux solutions : placer le playbook à la racine du projet, ou déclarer `roles_path` dans
> `ansible.cfg`.

### Dépendances de rôles

`meta/main.yml` peut déclarer `dependencies:` : ces rôles s'exécutent **avant**. À utiliser avec
parcimonie — une dépendance implicite est plus difficile à suivre qu'un appel explicite dans le
playbook, et elle se rejoue à chaque invocation.

## 4. Les collections

Une collection est l'unité de **distribution** d'Ansible : un espace de noms qui regroupe
modules, rôles, plugins et playbooks.

```
community/postgresql/
├── galaxy.yml              métadonnées de publication
├── meta/runtime.yml        requires_ansible, redirections
├── plugins/
│   ├── modules/
│   ├── lookup/
│   └── inventory/
├── roles/
└── playbooks/
```

L'appel se fait par **FQCN** : `<espace_de_noms>.<collection>.<objet>`, par exemple
`community.postgresql.postgresql_db`.

### Déclarer ses dépendances

```yaml
# collections/requirements.yml
collections:
  - name: ansible.posix
    version: ">=2.1.0"
  - name: community.postgresql
    version: ">=5.0.0,<6.0.0"
  - name: https://github.com/exemple/ma.collection.git
    type: git
    version: v1.4.0

roles:
  - name: geerlingguy.docker
    version: "7.6.0"
```

```bash
ansible-galaxy install -r requirements.yml              # rôles + collections
ansible-galaxy collection install -r requirements.yml   # collections seules
ansible-galaxy role install -r requirements.yml         # rôles seuls
```

> **Pourquoi déclarer ce que le paquet `ansible` contient déjà ?**
> Parce que la CI et les *execution environments* partent d'`ansible-core` **seul** (module 10),
> et parce que l'outillage ne voit que ce qui est déclaré. Démonstration : sans déclaration de
> `community.postgresql`, `ansible-lint` refuse le rôle —
> ```
> syntax-check[unknown-module]: couldn't resolve module/action
> 'community.postgresql.postgresql_db'
> ```
> Une fois la collection ajoutée à `collections/requirements.yml`, `ansible-lint` l'installe
> lui-même dans `.ansible/collections/` du projet et l'analyse aboutit. **Une dépendance non
> déclarée est une dépendance qui n'existe pas** pour la chaîne de qualité.

> **Attention**
> Pour les rôles, `version:` n'accepte **pas** de plage : un tag, une branche ou un commit,
> rien d'autre. Les collections acceptent les plages (`">=5.0.0,<6.0.0"`).

## 5. 🌌 Galaxy en 2026

| | Collections | Rôles autonomes |
|---|---|---|
| Peut contenir des modules et plugins | Oui | Non |
| Format recommandé | **Oui** | Hérité |
| Installation | `ansible-galaxy collection install` | `ansible-galaxy role install` |
| Hébergement | galaxy.ansible.com (galaxy_ng), Automation Hub | galaxy.ansible.com |

Les rôles autonomes restent installables, mais tout contenu nouveau se publie en collection.

### Trois niveaux de support

| Niveau | Qui teste | Qui supporte | Où |
|---|---|---|---|
| **Communautaire** | La communauté | Personne | galaxy.ansible.com |
| **Validé** | Red Hat | Best effort | Automation Hub |
| **Certifié** | Red Hat + partenaire | Red Hat (abonnement) | Automation Hub |

Un **hub privé** (galaxy_ng, inclus dans AAP) permet de miroiter Galaxy, de publier ses
collections internes et de signer le contenu. Galaxy a connu des indisponibilités début 2026 :
en production, prévoyez un miroir ou un cache.

## 6. 🔍 Évaluer un contenu avant de l'adopter

Reprendre un rôle Galaxy fait gagner du temps — à condition de le vérifier. La checklist :

| Signal | Où regarder | Ce qui alerte |
|---|---|---|
| Dernière publication | Galaxy, dépôt Git | Plus de 12 mois |
| Version d'Ansible requise | `meta/runtime.yml`, `meta/main.yml` | `>=2.9` : trop laxiste, jamais retesté |
| **Matrice de CI réelle** | `.github/workflows/` | Votre OS absent ou **commenté** |
| Tests | `molecule/` présent et exécuté | Aucun test |
| Licence | `LICENSE` | Incompatible avec votre usage |
| Mainteneurs | Dépôt | Un seul, inactif |

> **Attention — `platforms:` n'est pas une garantie**
> Le bloc `platforms:` de `meta/main.yml` est déclaratif : personne ne le vérifie. Cas réel en
> 2026 : `geerlingguy.postgresql` 4.1.0 fournit bien un fichier `vars/RedHat-10.yml`, mais y
> déclare `__postgresql_version: "13"` alors que Rocky 10 livre PostgreSQL **16**, et les entrées
> `rockylinux10` de sa CI sont **commentées**. Le rôle *annonce* le support, il ne le *teste*
> pas. C'est la matrice de CI qui fait foi, pas les métadonnées.

Trois commandes utiles :

```bash
ansible-galaxy collection list                          # ce qui est installé, et où
ansible-galaxy collection verify community.postgresql   # intégrité vs Galaxy
ansible-galaxy role info geerlingguy.docker             # métadonnées d'un rôle
```

### Surcharger sans dupliquer

Un rôle externe presque adapté ne se duplique pas. Par ordre de préférence :

1. **Le paramétrer** avec ses variables.
2. **L'encadrer** : un rôle maison qui l'appelle en `import_role` et ajoute les tâches manquantes.
3. **L'épingler puis contribuer** en amont.
4. En dernier recours, le forker — en notant la dette.

---

## TP 05 — Du playbook aux rôles

**Durée : 35 min.** Corrigé : [`corrige/tp05-roles/`](../corrige/tp05-roles/)

### Objectif

Restructurer le fil rouge en rôles, et installer PostgreSQL sur `db01` avec une collection.

> **Passer au rôle.** `tasks/main.yml` reçoit la liste de tâches, sans les clés `hosts:`,
> `become:` et `tasks:` du play. Le play de `site.yml` choisit les machines et appelle le
> rôle. Renommez aussi les variables dans les templates quand vous ajoutez le préfixe
> `nginx_`. Le rôle `postgres` est votre code d'installation ; `community.postgresql`
> lui fournit les modules qui manipulent les bases et les comptes SQL.

### Énoncé

1. **Créer le rôle `base`** à partir du playbook du TP 03 : tâches, gabarit `hosts.j2`,
   `defaults/main.yml` pour `base_admin_user` et le chemin de la clé publique.

2. **Créer le rôle `nginx`** à partir du playbook du TP 04 :
   - `defaults/` : `nginx_sites` (vide), `nginx_site_racine`, `nginx_port_defaut`,
     `nginx_supprimer_site_defaut`, `nginx_verifier` ;
   - `vars/` : dictionnaire `nginx_chemins` indexé par `os_family`, rendant le rôle utilisable
     sur Debian **et** RedHat ;
   - `handlers/` : contrôle puis rechargement, abonnés au sujet `configuration nginx modifiee` ;
   - `meta/argument_specs.yml` validant `nginx_sites`, y compris les clés de chaque site et les
     valeurs autorisées de `log_level`.

3. **Créer le rôle `postgres`** pour Rocky Linux 10 :
   - installer `postgresql-server`, `postgresql-contrib`, `python3-psycopg2` (exigé par la
     collection) et `python3-libselinux` (exigé par Ansible quand SELinux est actif) ;
   - initialiser le répertoire de données avec `postgresql-setup --initdb`, **idempotent** grâce
     à `creates` ;
   - démarrer et activer le service ;
   - créer bases et comptes avec `community.postgresql`, en exécutant les tâches SQL en
     `become_user: postgres` ;
   - ouvrir le port dans `firewalld`, actif par défaut sur Rocky.

4. **Écrire `site.yml`** à la racine du projet : trois plays (`all` → `base`, `web` → `nginx`,
   `db` → `postgres`) qui ne contiennent **que** des données.

5. **Déclarer les dépendances** dans `requirements.yml` : `ansible.posix`, `community.general`,
   `community.postgresql`.

6. **Vérifier la validation des arguments** : donner à `log_level` une valeur hors de la liste
   autorisée et constater que l'exécution s'arrête avant la première tâche.

### Déroulé attendu

```bash
ansible-galaxy install -r requirements.yml
ansible-lint .
ansible-playbook site.yml --list-tasks
ansible-playbook site.yml
ansible-playbook site.yml          # idempotence
ansible-playbook site.yml --check --diff   # PostgreSQL doit déjà être installé
```

`--list-tasks` doit faire apparaître la validation des arguments :

```console
  play #2 (web): Deploiement des serveurs web
      nginx : Validating arguments against arg spec 'main' - Deploiement de sites nginx  TAGS: [always]
      nginx : Selectionner les chemins propres a la distribution
      ...
```

### Points d'attention

> **Deux comptes distincts.** `become_user: postgres` choisit le compte **Linux** qui exécute
> le module. L'authentification locale *peer* permet ensuite à ce compte d'administrer
> PostgreSQL par socket Unix. Le compte SQL `applicatif` est créé pour l'application : il
> n'est pas un utilisateur SSH. Ouvrir le pare-feu ne suffit pas à autoriser des connexions
> SQL distantes ; l'écoute et les règles PostgreSQL doivent aussi les permettre.

- **`site.yml` va à la racine du projet**, pas dans `playbooks/` : sinon `roles/` n'est pas
  trouvé.
- Les tâches `community.postgresql` s'exécutent en `become_user: postgres` (authentification
  *peer* par socket Unix).
- `no_log: true` sur la création des comptes : sans cela, le mot de passe apparaît dans la sortie.
- Le mot de passe est encore en clair dans `site.yml`. Il sera chiffré au module 11.
- `postgresql_user` peut se signaler `changed` à chaque exécution : PostgreSQL stocke une
  empreinte et ne permet pas de comparer le mot de passe fourni.

### ⚠️ Pièges courants

| Symptôme | Cause |
|---|---|
| `the role 'base' was not found` | Playbook dans `playbooks/`, rôles à la racine |
| `couldn't resolve module/action 'community.postgresql...'` | Collection non déclarée dans `requirements.yml` |
| `$.roles None is not of type 'array'` | Clé `roles:` sans élément — écrire `roles: []` |
| `Validation of arguments failed` | C'est le résultat attendu à l'étape 6 |
| Lien symbolique circulaire sur Rocky | `sites-available` et `conf.d` confondus : conditionner la tâche |

### 🚀 Pour aller plus loin

- `ansible-doc -t role formation.nginx` : la documentation est générée depuis `argument_specs.yml`.
- Comparer votre rôle `postgres` à `geerlingguy.postgresql` : lire sa CI et constater que
  `rockylinux10` y est commenté.
- Appliquer le rôle `nginx` à `db01` (Rocky) et vérifier que `vars/main.yml` suffit à l'adapter.

---

## 🔑 Points clés

- `defaults/` = ce que l'appelant règle ; `vars/` = ce qu'il ne doit pas toucher.
- **Préfixez les variables** par le nom du rôle.
- `meta/argument_specs.yml` déplace les erreurs **avant la première tâche**.
- `import_role` est statique et visible par `--list-tasks` ; `include_role` est dynamique.
- Le chemin de recherche des rôles part du **répertoire du playbook**.
- **Déclarez vos collections** : ce qui n'est pas dans `requirements.yml` n'existe pas pour la CI
  ni pour `ansible-lint`.
- `version:` accepte une plage pour une collection, **pas** pour un rôle.
- **La matrice de CI fait foi**, pas le bloc `platforms:` des métadonnées.

---

**Module précédent :** [05 — Variables, Jinja2, handlers](05-Variables-Jinja-Handlers.md)
**Module suivant :** [07 — Exécution avancée](../J2-Industrialisation/07-Execution-Avancee.md)
