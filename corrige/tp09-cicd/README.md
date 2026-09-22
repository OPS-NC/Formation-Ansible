# TP 09 — Chaîne d'intégration du projet

Énoncé : [module 10](../../J2-Industrialisation/10-Git-CICD.md#tp-09--chaîne-dintégration-du-projet)

## Contenu

```
.pre-commit-config.yaml          filtre local : yamllint, ansible-lint, clés privées
.gitlab-ci.yml                   4 étapes : lint, test, check, deploy
.github/workflows/ansible.yml    équivalent GitHub Actions, avec matrice Molecule
execution-environment.yml        image d'exécution reproductible (format v3)
```

Ces fichiers se placent **à la racine du projet**, pas dans un sous-répertoire.

## Le workflow réellement actif

Ce dépôt de formation utilise une version simplifiée du workflow GitHub :
[`.github/workflows/lint.yml`](../../.github/workflows/lint.yml). Il valide tous les corrigés
au profil `production` à chaque poussée.

## Vérification

```bash
# Filtre local
pipx install pre-commit
pre-commit install
pre-commit run --all-files

# Execution environment (outils absents du module 02, a installer)
pipx install ansible-builder
pipx install ansible-navigator
ansible-builder build -t formation-ee:1.0 -f execution-environment.yml
podman run --rm formation-ee:1.0 ansible-galaxy collection list
ansible-navigator run site.yml --eei formation-ee:1.0 -m stdout
```

## Les quatre étapes

| Étape | Commande | Déclenchement |
|---|---|---|
| `lint` | `ansible-lint --profile production --offline` | chaque poussée |
| `test` | `molecule test --workers cpus-1` | modification d'un rôle |
| `check` | `ansible-playbook --check --diff` sur `dev` | chaque fusion |
| `deploy` | `ansible-playbook` sur `prod` | manuel, sur étiquette |

## Points sensibles

**Secrets.** Le mot de passe vault vient d'une variable masquée, est écrit dans un fichier en
mode 600, et supprimé dans `after_script` — qui s'exécute même en cas d'échec, contrairement à
`script`.

**Molecule en CI.** Faire tourner des conteneurs dans un conteneur de CI est le point qui échoue
le plus souvent. Sur un exécuteur Docker, podman rootless exige `privileged = true` ou
`--device /dev/fuse` avec `SYS_ADMIN`. Sans cela, `STORAGE_DRIVER=vfs` fonctionne, plus
lentement.

**Execution environment.** Il part de `ansible-core` **seul**. Tout ce qui n'est pas déclaré
dans `collections/requirements.yml` est absent de l'image : construire l'EE est le test le plus
honnête de ce fichier.

> À valider sur la machine Ubuntu : la construction effective de l'EE avec `ansible-builder`
> et l'exécution de Molecule dans un exécuteur de CI. Les fichiers ont été validés
> syntaxiquement, mais aucune image n'a été construite lors de la rédaction.
