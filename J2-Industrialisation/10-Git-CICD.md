# Module 10 — Git, CI/CD et execution environments

> **Jour 2** · 90 min · Théorie + **TP 09**
> Prérequis : [module 09](09-Qualite.md).

## Objectifs

- Organiser un dépôt Ansible et sa gestion de versions.
- Construire une chaîne d'intégration qui refuse le code non conforme.
- Comprendre ce qu'apporte un *execution environment* et en construire un.

---

## 1. Structure du dépôt

```
formation-ansible/
├── ansible.cfg
├── site.yml                      point d'entrée
├── collections/
│   └── requirements.yml          dépendances externes
├── inventories/
│   ├── dev/
│   │   ├── hosts.yml
│   │   ├── group_vars/
│   │   └── host_vars/
│   └── prod/
├── playbooks/                     playbooks spécialisés (patching, sauvegarde)
├── roles/
│   ├── base/
│   └── nginx/
├── execution-environment.yml
├── .ansible-lint
├── .yamllint
├── .pre-commit-config.yaml
└── .gitlab-ci.yml
```

Deux règles structurent le reste.

**Un environnement, un inventaire.** `dev` et `prod` ne diffèrent que par leurs inventaires et
leurs variables. Le même `site.yml` s'applique aux deux ; c'est la seule façon de garantir que
ce qui a été validé en développement est bien ce qui part en production.

**Ce qui est généré n'est pas versionné.** `collections/ansible_collections/`, `.vagrant/`,
`facts_cache/`, `*.retry`, et surtout tout fichier de mot de passe.

```gitignore
.vagrant/
*.retry
.vault_pass
collections/ansible_collections/
facts_cache/
.ansible/
```

> **Attention**
> `detect-private-key` dans les hooks pre-commit n'est pas une précaution théorique. Une clé
> privée poussée sur un dépôt distant doit être considérée comme compromise, même après
> réécriture de l'historique.

## 2. Gestion de versions

- **Branches courtes** et fusion par demande de fusion. La branche principale doit rester
  applicable en production à tout instant.
- **Revue obligatoire** : la CI vérifie la forme, la revue vérifie l'intention.
- **Étiquettes SemVer** sur la branche principale. Le déploiement en production se déclenche sur
  une étiquette, pas sur une fusion : on sait ainsi exactement ce qui tourne.
- **Dépendances épinglées** dans `requirements.yml`. Une plage non bornée rend la CI
  irreproductible.

## 3. Pre-commit

Le premier filtre, le moins cher : il s'exécute avant le commit, donc avant la CI.

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: check-merge-conflict
      - id: detect-private-key

  - repo: https://github.com/adrienverge/yamllint
    rev: v1.38.0
    hooks:
      - id: yamllint
        args: [--strict]

  - repo: https://github.com/ansible/ansible-lint
    rev: v26.8.0
    hooks:
      - id: ansible-lint
        additional_dependencies:
          - "ansible-core>=2.21.0"
```

```bash
pipx install pre-commit
pre-commit install          # active le hook git
pre-commit run --all-files  # passage manuel sur tout le dépôt
```

> Pre-commit ne remplace pas la CI : il se contourne avec `--no-verify`. C'est un confort pour
> le développeur, pas une garantie.

## 4. La chaîne d'intégration

Quatre étapes, du moins cher au plus cher :

| Étape | Contenu | Durée | Déclenchement | Joint des machines ? |
|---|---|---|---|---|
| `lint` | `ansible-lint --profile production` | secondes | Chaque poussée | Non |
| `test` | `molecule test` | minutes | Modification d'un rôle | Non, conteneurs |
| `check` | `ansible-playbook --check --diff` sur `dev` | minutes | Chaque fusion | **Oui** |
| `deploy` | Application réelle sur `prod` | — | Manuel, sur étiquette | **Oui** |

> **Attention — les deux dernières étapes ont des prérequis d'infrastructure**
> `lint` et `test` tournent n'importe où. `check` et `deploy` joignent de vraies machines, ce qui
> impose deux conditions rarement anticipées :
> - **une route vers le parc.** Un exécuteur hébergé n'a aucun accès au réseau host-only du lab.
>   Il faut un exécuteur installé sur une machine qui le voit, sélectionné par étiquette ;
> - **une identité SSH issue d'un secret CI.** Les clés de `.vagrant/` sont propres au poste du
>   stagiaire, exclues de Git et absentes du checkout. On utilise le compte de service créé au
>   TP 03 et une clé dédiée.

### GitLab CI

```yaml
stages: [lint, test, check, deploy]

default:
  image: ghcr.io/ansible/community-ansible-dev-tools:latest
  before_script:
    - ansible-galaxy collection install -r collections/requirements.yml

variables:
  STORAGE_DRIVER: vfs
  BUILDAH_ISOLATION: chroot

lint:
  stage: lint
  script:
    - ansible-lint --profile production --offline

molecule:
  stage: test
  script:
    - cd roles/nginx
    - molecule test --workers cpus-1
  rules:
    - changes: [roles/**/*]

deploy:
  stage: deploy
  script:
    - echo "$VAULT_PASSWORD" > .vault_pass
    - chmod 600 .vault_pass
    - ansible-playbook site.yml -i inventories/prod/ --vault-password-file .vault_pass
  after_script:
    - rm -f .vault_pass
  when: manual
  rules:
    - if: $CI_COMMIT_TAG
```

L'image `ghcr.io/ansible/community-ansible-dev-tools` réunit `ansible-core`, `ansible-lint`,
`molecule`, `ansible-navigator`, `ansible-creator` et podman-in-podman.

> **Attention — Molecule en CI**
> Faire tourner des conteneurs **dans** un conteneur de CI est le point qui échoue le plus
> souvent. Sur un exécuteur Docker, podman rootless exige soit `privileged = true` dans la
> configuration de l'exécuteur, soit `--device /dev/fuse` avec la capacité `SYS_ADMIN`. Sans
> `/dev/fuse`, basculez le pilote de stockage sur `vfs` : plus lent, mais fonctionnel. Le
> Docker-in-Docker classique est incompatible avec les conteneurs systemd sans `--cgroupns=host`.

### GitHub Actions

```yaml
jobs:
  lint:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
      - uses: ansible/ansible-lint@v26.8.0
        with:
          args: "--profile production"
          setup_python: "true"
          requirements_file: "collections/requirements.yml"
```

L'action officielle installe Python, les collections déclarées, puis lance l'analyse. Entrées
principales : `args`, `setup_python`, `python_version`, `working_directory`,
`requirements_file`, `expected_return_code`.

> Ce dépôt de formation utilise ce workflow réellement :
> [`.github/workflows/lint.yml`](../.github/workflows/lint.yml) valide tous les corrigés à chaque
> poussée.

### Secrets en CI

| Méthode | Usage |
|---|---|
| Variable masquée → fichier temporaire | Mot de passe vault. Le plus simple. |
| SOPS + age, clé en variable | Diffs lisibles en revue (module 11) |
| OIDC vers HashiCorp Vault ou OpenBao | Jetons de courte durée, sans secret stocké |

```yaml
script:
  - echo "$VAULT_PASSWORD" > .vault_pass
  - chmod 600 .vault_pass
  - ansible-playbook site.yml --vault-password-file .vault_pass
after_script:
  - rm -f .vault_pass      # exécuté même en cas d'échec
```

> Le nettoyage va dans `after_script`, qui s'exécute quoi qu'il arrive. Dans `script`, un échec
> laisserait le fichier sur l'exécuteur.

## 5. Execution environments

### Le problème

Le poste du développeur a le paquet `ansible` et ses 90 collections. L'exécuteur de CI a autre
chose. Le serveur d'ordonnancement a encore autre chose. Un playbook qui fonctionne ici échoue
là, pour une raison invisible.

Un **execution environment** est une image conteneur figeant `ansible-core`, les collections et
leurs dépendances système et Python. Les trois environnements exécutent alors strictement la
même chose.

### Construire

```yaml
# execution-environment.yml — format v3
version: 3

images:
  base_image:
    name: ghcr.io/ansible/community-ee-base:latest

dependencies:
  ansible_core:
    package_pip: ansible-core>=2.21,<2.22
  ansible_runner:
    package_pip: ansible-runner
  galaxy: collections/requirements.yml
  python:
    - psycopg2-binary
    - kubernetes>=24.2.0
  system:
    - openssh-clients [platform:rpm]

additional_build_steps:
  append_final:
    - RUN ansible-galaxy collection list
```

Ces deux outils ne font pas partie des trois installations du module 02 : il faut les ajouter.

```bash
pipx install ansible-builder
pipx install ansible-navigator

ansible-builder build -t formation-ee:1.0 -f execution-environment.yml
```

On part d'`ansible-core` **seul** : c'est `collections/requirements.yml` qui décrit le reste.
Un projet dont les dépendances ne sont pas déclarées ne peut pas être empaqueté — la construction
de l'EE est le test le plus honnête de cette déclaration.

> **Ce que contient l'EE.** L'image fournit l'outillage ; le projet, l'inventaire et les
> identifiants lui sont fournis au lancement. Le conteneur devient le contexte d'exécution
> d'Ansible, mais les VMs restent les cibles. Un chemin présent sur votre poste n'existe
> dans le conteneur que s'il y est monté : cela concerne notamment les clés SSH.

### Exécuter

```bash
ansible-navigator run site.yml --eei formation-ee:1.0
ansible-navigator run site.yml --execution-environment false   # sans conteneur
```

`ansible-navigator` est aussi une interface texte pour explorer une exécution :
`ansible-navigator run site.yml` puis navigation dans les plays, tâches et résultats.

`ansible-runner` est la bibliothèque qui exécute Ansible dans un EE. C'est elle qu'utilisent
AWX et AAP (module 12), et elle permet de lancer un playbook comme tâche Kubernetes (module 15).

---

## TP 09 — Chaîne d'intégration du projet

**Durée : 40 min.** Corrigé : [`corrige/tp09-cicd/`](../corrige/tp09-cicd/)

### Objectif

Doter le projet d'un filtre local et d'une chaîne d'intégration, puis l'empaqueter.

> **Du poste à la CI.** Un runner (exécuteur) est la machine qui lance les commandes des
> jobs. Il récupère les fichiers versionnés, sans vos fichiers locaux ignorés par Git.
> La CI vérifie le projet ; le job `deploy` applique réellement sa configuration aux cibles.
> Le lab fournit seulement `dev` : `prod` représente ici l'organisation à préparer, pas
> un second parc déjà disponible. Sans runner relié au lab, la partie distante reste une
> lecture de configuration ; les contrôles locaux et la construction de l'EE restent réalisables.
>
> Le mot de passe Vault mentionné dans le pipeline sera créé au TP 10. Jusqu'à ce TP,
> distinguez la préparation du job de son exécution avec des fichiers chiffrés.

### Énoncé

1. **Structurer le dépôt** : `site.yml` à la racine, `inventories/dev/` et `inventories/prod/`,
   `roles/`, `collections/requirements.yml`. Compléter le `.gitignore`.

2. **Installer pre-commit** avec `yamllint`, `ansible-lint` et `detect-private-key`.
   Vérifier qu'un fichier mal indenté ou une clé privée bloque le commit.

3. **Écrire la chaîne d'intégration** de la plateforme disponible (GitLab CI ou GitHub Actions)
   avec les quatre étapes `lint`, `test`, `check`, `deploy` :
   - `deploy` **manuel** et conditionné à une étiquette ;
   - le mot de passe vault vient d'une variable masquée et le fichier temporaire est supprimé
     dans `after_script`.

4. **Construire un execution environment** :
   ```bash
   ansible-builder build -t formation-ee:1.0 -f execution-environment.yml
   podman run --rm formation-ee:1.0 ansible-galaxy collection list
   ```

5. **Exécuter le fil rouge dans l'EE** :
   ```bash
   ansible-navigator run site.yml --eei formation-ee:1.0 -m stdout
   ```

6. **Provoquer un échec utile** : retirer `community.postgresql` de
   `collections/requirements.yml`, reconstruire l'EE, et constater que le rôle `postgres` ne
   fonctionne plus. C'est la démonstration que la déclaration des dépendances n'est pas
   facultative.

### Points d'attention

- `after_script` pour le nettoyage des secrets : il s'exécute même en cas d'échec.
- Molecule en CI nécessite des privilèges particuliers pour les conteneurs imbriqués.
- L'EE part d'`ansible-core` seul : tout ce qui n'est pas déclaré est absent.
- `--offline` sur `ansible-lint` en CI évite une dépendance au réseau.

### Pièges courants

| Symptôme | Cause |
|---|---|
| `pre-commit` ne se déclenche pas | `pre-commit install` non lancé |
| Molecule échoue en CI mais passe en local | Conteneurs imbriqués sans privilèges |
| L'EE ne trouve pas un module | Collection absente de `requirements.yml` |
| Le mot de passe vault reste sur l'exécuteur | Nettoyage placé dans `script` |
| `deploy` part à chaque fusion | Condition sur l'étiquette absente |

### Pour aller plus loin

- Ajouter un job publiant le rôle comme collection interne sur un hub privé.
- Comparer la durée d'exécution avec et sans EE.
- Ajouter `ansible-lint --fix` en mode vérification : la CI échoue si `--fix` aurait modifié
  quelque chose.

---

## Points clés

- **Un environnement, un inventaire** ; un seul `site.yml` pour tous.
- **Rien de généré n'est versionné**, et surtout aucun secret.
- Pre-commit filtre localement, la CI garantit — l'un se contourne, pas l'autre.
- Le déploiement en production est **manuel et sur étiquette**.
- Les secrets se nettoient dans **`after_script`**.
- Un **execution environment** aligne poste, CI et ordonnanceur sur le même socle.
- Construire l'EE est le test le plus honnête de `collections/requirements.yml`.

---

**Module précédent :** [09 — Qualité : lint et tests](09-Qualite.md)
**Module suivant :** [11 — Gestion des secrets](11-Secrets.md)
