# Module 09 — Qualité : analyse statique et tests

> **Jour 2** · 75 min · Théorie + **TP 08**
> Prérequis : [module 08](08-Inventaires-Dynamiques.md).

## Objectifs

- Faire passer un rôle au profil `production` d'`ansible-lint`.
- Écrire un scénario Molecule au format actuel et tester sur deux distributions.
- Automatiser le test d'idempotence.
- Situer chaque outil dans une chaîne de vérification.

---

## 1. La chaîne de vérification

| Niveau | Outil | Ce qu'il détecte | Coût |
|---|---|---|---|
| 1 | `--syntax-check` | YAML invalide, module inconnu | Instantané |
| 2 | `ansible-lint` | Anti-patrons, sécurité, nommage, idempotence probable | Secondes |
| 3 | `--check --diff` | Écart entre l'état voulu et l'état réel | Minutes, sur le parc |
| 4 | **Molecule** | Le rôle fonctionne réellement, sur un système neuf | Minutes, isolé |
| 5 | `ansible-test` | Tests unitaires et d'intégration d'une collection | Minutes |

Chaque niveau attrape ce que le précédent laisse passer. Aucun ne remplace les autres.

## 2. ansible-lint

### Les profils

Les profils sont **cumulatifs**. Chacun inclut les précédents :

```
min → basic → moderate → safety → shared → production
```

| Profil | Ce qu'il ajoute |
|---|---|
| `min` | Ce qui empêche Ansible de fonctionner |
| `basic` | Conventions de base, `var-naming` |
| `moderate` | Lisibilité, `name[casing]`, ordre des clés |
| `safety` | `package-latest`, `risky-file-permissions`, `risky-shell-pipe`, `risky-octal` |
| `shared` | Ce qu'exige du contenu partagé : `no-changed-when`, `meta-runtime`, `galaxy`, `max-tasks` |
| **`production`** | `fqcn`, `avoid-dot-notation`, `import-task-no-when`, `meta-no-dependencies`, `single-entry-point`, `use-loop`, `sanity` |

> `production` n'ajoute que sept règles. L'essentiel du travail est fait par les profils
> inférieurs. Un rôle n'a **pas** besoin de `meta/runtime.yml` ni de `galaxy.yml` pour le passer.

### Configuration

```yaml
# .ansible-lint
---
profile: production

exclude_paths:
  - .vagrant/
  - collections/
  - .ansible/

warn_list:
  - package-latest      # signalé, mais non bloquant

skip_list: []           # ignoré totalement — à éviter
mock_roles: []          # rôles absents du poste de lint
mock_modules: []
```

Trois niveaux de tolérance, par ordre de préférence :

1. **Corriger.**
2. `# noqa: <règle>` en fin de ligne — exception locale, visible en revue.
3. `warn_list` — signalé sans bloquer, à résorber.
4. `skip_list` — désactivation globale. À justifier par écrit.

```yaml
- name: Mettre a jour tous les paquets
  ansible.builtin.package:
    name: "*"
    state: latest      # noqa package-latest
```

### Les règles les plus souvent rencontrées

| Règle | Correction |
|---|---|
| `fqcn[action-core]` | `ansible.builtin.copy` au lieu de `copy` |
| `name[missing]`, `name[casing]` | Nommer chaque tâche, majuscule initiale |
| `no-changed-when` | `changed_when` sur `command` / `shell` |
| `risky-file-permissions` | `mode:` explicite sur `file`, `copy`, `template` |
| `risky-octal` | `mode: "0644"` entre guillemets, jamais `0644` nu |
| `var-naming[no-role-prefix]` | Préfixer les variables **et les `register`** d'un rôle |
| `package-latest` | `state: present` plutôt que `latest` |
| `meta-no-dependencies` | Appeler les rôles depuis le playbook |
| `single-entry-point` | Un rôle doit avoir `tasks/main.yml` |

> **Attention**
> `var-naming[no-role-prefix]` s'applique aussi aux variables `register` situées dans un rôle,
> y compris dans un scénario Molecule rangé sous le rôle. `register: page` devient
> `register: nginx_page`.

### Correction automatique

```bash
ansible-lint --fix              # applique toutes les transformations disponibles
ansible-lint --fix=fqcn,name    # sélectivement
```

`--fix` reformate le YAML et traite notamment `fqcn`, `name`, `key-order`, `jinja`,
`no-free-form`, `partial-become`, `no-log-password`. **Relisez le différentiel** : l'outil
reformate parfois plus que prévu.

## 3. Molecule

Molecule crée un environnement jetable, y applique le rôle, vérifie le résultat, et détruit.

### Le format a changé

Depuis **Molecule 25.9**, le modèle est dit **ansible-native**. Les clés historiques `driver`,
`platforms` et `provisioner` sont désormais documentées comme « pre ansible-native » et
conservées pour compatibilité. Beaucoup de tutoriels en ligne décrivent encore l'ancien format.

Dans le format actuel, l'infrastructure de test est décrite **avec Ansible** : un inventaire,
un `create.yml` et un `destroy.yml`.

```
roles/nginx/molecule/default/
├── molecule.yml          configuration
├── requirements.yml      collections nécessaires aux tests
├── inventory/hosts.yml   les machines de test
├── create.yml            démarrage
├── destroy.yml           suppression
├── converge.yml          application du rôle  ← le cœur
└── verify.yml            assertions
```

```yaml
# molecule.yml
---
ansible:
  cfg:
    defaults:
      deprecation_warnings: false
      callback_result_format: yaml
  executor:
    backend: ansible-playbook
    args:
      ansible_playbook:
        - --inventory=inventory/

dependency:
  name: galaxy
  options:
    requirements-file: ${MOLECULE_SCENARIO_DIRECTORY}/requirements.yml

scenario:
  test_sequence:
    - dependency
    - destroy
    - create
    - converge
    - idempotence
    - verify
    - destroy
```

> **Attention — validation stricte**
> Le schéma de `molecule.yml` interdit toute clé inconnue. Une faute de frappe produit
> immédiatement :
> ```
> ERROR   Failed to validate .../molecule/default/molecule.yml
> ```
> C'est vérifiable sans conteneur : `molecule list` analyse la configuration et s'arrête là.

### L'inventaire de test

```yaml
all:
  children:
    molecule:
      hosts:
        debian13:
          container_image: docker.io/geerlingguy/docker-debian13-ansible:latest
        rocky10:
          container_image: docker.io/geerlingguy/docker-rockylinux10-ansible:latest
      vars:
        ansible_connection: containers.podman.podman
        container_command: /sbin/init
        container_systemd: always
```

> **Attention — il faut systemd**
> Un rôle qui démarre un service ne peut pas être testé dans un conteneur ordinaire.
> `debian:trixie` et `rockylinux/rockylinux:10` n'embarquent pas systemd. Les images
> `geerlingguy/docker-*-ansible` sont construites pour cela. Côté Rocky, la variante officielle
> adaptée est `rockylinux/rockylinux:10-ubi-init`.
> `container_systemd: always` force le mode systemd de podman ; la valeur `true` se contente
> d'une autodétection, mise en défaut dès qu'on fournit `command`.

### La séquence de test

Sans `test_sequence` explicite, `molecule test` enchaîne :

```
dependency → cleanup → destroy → syntax → create → prepare
          → converge → idempotence → side_effect → verify → cleanup → destroy
```

**`idempotence` rejoue `converge` et échoue si une seule tâche rapporte `changed`.** C'est le
test du module 04, automatisé.

### Les commandes

```bash
molecule list                # analyse la configuration, ne crée rien
molecule create              # crée l'environnement
molecule converge            # applique le rôle (itération rapide)
molecule verify              # joue les assertions
molecule idempotence         # rejoue converge et vérifie l'absence de changed
molecule test                # séquence complète, avec destruction
molecule destroy
molecule test -s <scenario> --workers cpus-1
```

Pendant la mise au point, on enchaîne `converge` autant de fois que nécessaire sans détruire.
`molecule test` n'intervient qu'à la fin, ou en CI.

> `--parallel` est déprécié : utilisez `--workers`.

### Les vérifications

`verify.yml` est un playbook ordinaire. Les assertions y sont écrites avec
`ansible.builtin.assert` :

```yaml
- name: Le service nginx doit etre actif
  ansible.builtin.assert:
    that:
      - ansible_facts['services']['nginx.service']['state'] == 'running'
    fail_msg: nginx n est pas demarre
```

Vérifiez le **résultat**, pas la mécanique : un service qui répond, un fichier au bon endroit,
une configuration acceptée par le démon. Rejouer les tâches du rôle ne teste rien.

## 4. Tester une collection

Pour une collection, l'outil est `ansible-test` :

```bash
ansible-test sanity --docker        # cohérence, documentation, conventions
ansible-test units --docker         # tests unitaires Python des modules
ansible-test integration --docker   # tests d'intégration
```

`ansible-test sanity` est le minimum avant toute publication sur Galaxy.

---

## TP 08 — Mettre le rôle sous qualité

**Durée : 35 min.** Corrigé : [`corrige/tp08-qualite/`](../corrige/tp08-qualite/)

### Objectif

Amener le rôle `nginx` au profil `production`, puis le tester automatiquement sur Debian 13 et
Rocky Linux 10.

### Prérequis

> **Ce que vous testez.** Reprenez le rôle `nginx` du TP 05. Molecule crée ses propres
> conteneurs `debian13` et `rocky10`, indépendants de `web01` et `db01` ; son inventaire
> utilise Podman au lieu de SSH. `converge.yml` appelle le rôle avec des données de test,
> `verify.yml` observe le service obtenu. Un `changed=0` au second passage ne suffit pas
> à prouver que le site répond : c'est pourquoi les deux vérifications sont nécessaires.

```bash
pipx install molecule
sudo apt install -y podman
ansible-galaxy collection install containers.podman
```

### Énoncé

1. **Créer `.ansible-lint`** au profil `production`, avec les exclusions utiles et
   `package-latest` en `warn_list`.

2. **Corriger les écarts** jusqu'à obtenir zéro violation :
   ```bash
   ansible-lint --profile production .
   ```
   Traiter au moins : FQCN manquants, `mode:` absent, `changed_when` manquant, noms de tâches en
   minuscule, variables `register` non préfixées.

3. **Écrire le scénario Molecule** dans `roles/nginx/molecule/default/`, au format
   ansible-native : `molecule.yml`, `requirements.yml`, `inventory/hosts.yml`, `create.yml`,
   `destroy.yml`, `converge.yml`, `verify.yml`.

4. **Vérifier la configuration sans rien créer :**
   ```bash
   cd roles/nginx && molecule list
   ```

5. **Écrire `verify.yml`** avec au moins cinq assertions : service actif, présence des trois
   vhosts, configuration acceptée par `nginx -t`, absence du site par défaut, contenu de la page
   d'accueil.

6. **Dérouler le scénario :**
   ```bash
   molecule create
   molecule converge
   molecule verify
   molecule test          # séquence complète, idempotence comprise
   ```

7. **Provoquer un échec d'idempotence** : ajouter au rôle une tâche `command` sans
   `changed_when`, relancer `molecule test` et constater l'arrêt à l'étape `idempotence`.

   Retirer ensuite la tâche ajoutée pour l'expérience et retrouver un scénario réussi avant
   de passer à la CI.

### Points d'attention

- Le scénario vit **dans le rôle**, pas à la racine du projet.
- `ansible-lint` ne connaît pas le chemin des rôles que Molecule fournit à l'exécution.
  `converge.yml` produit alors `The role 'nginx' was not found`. Deux corrections possibles :
  ajouter le répertoire parent à `roles_path` dans `ansible.cfg` (ou à `ANSIBLE_ROLES_PATH`),
  ce qui **résout** réellement le rôle, ou déclarer `mock_roles: [nginx]`, qui se contente de le
  **simuler**. Préférez la première.
- Toute collection utilisée par les tests doit être déclarée, y compris `containers.podman`.
- `container_systemd: always`, et non `true`.

### Pièges courants

| Symptôme | Cause |
|---|---|
| `Failed to validate molecule.yml` | Clé inconnue — le schéma est strict |
| Le service ne démarre pas dans le conteneur | Image sans systemd |
| `couldn't resolve module/action 'containers.podman...'` | Collection non déclarée |
| `The role 'nginx' was not found` au lint | `roles_path` non renseigné |
| Échec à l'étape `idempotence` | Une tâche rapporte `changed` au second passage |
| `var-naming[no-role-prefix]` dans `verify.yml` | `register` non préfixé par le nom du rôle |

### Pour aller plus loin

- Ajouter un scénario `molecule/rocky-seul/` et le lancer avec `-s rocky-seul`.
- Lancer `ansible-lint --fix` sur une copie et lire attentivement le différentiel produit.
- Chronométrer `molecule test` avec `--workers cpus-1`.

---

## Points clés

- Les profils `ansible-lint` sont **cumulatifs** ; `production` n'ajoute que sept règles.
- Corriger > `# noqa` > `warn_list` > `skip_list`.
- `var-naming[no-role-prefix]` vise aussi les `register` d'un rôle.
- **Molecule a changé de format** : le modèle ansible-native décrit les tests avec Ansible.
- Le schéma de `molecule.yml` est **strict** ; `molecule list` le valide sans conteneur.
- Tester un service exige une **image avec systemd**.
- `idempotence` automatise le test du module 04 : aucun `changed` au second passage.
- `verify.yml` vérifie des **résultats**, pas la mécanique du rôle.

---

**Module précédent :** [08 — Inventaires dynamiques](08-Inventaires-Dynamiques.md)
**Module suivant :** [10 — Git et CI/CD](10-Git-CICD.md)
