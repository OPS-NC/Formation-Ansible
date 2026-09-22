# TP 08 — Qualité : ansible-lint et Molecule

Énoncé : [module 09](../../J2-Industrialisation/09-Qualite.md#tp-08--mettre-le-rôle-sous-qualité)

## Contenu

```
.ansible-lint                        configuration de référence, profil production
```

Le scénario Molecule vit **dans le rôle**, à son emplacement normal :

```
../tp05-roles/roles/nginx/molecule/default/
├── molecule.yml                     configuration ansible-native
├── requirements.yml                 containers.podman, ansible.posix
├── inventory/hosts.yml              deux conteneurs : Debian 13 et Rocky 10
├── create.yml                       démarrage des conteneurs
├── destroy.yml                      suppression
├── converge.yml                     application du rôle
└── verify.yml                       7 assertions post-déploiement
```

## Vérification

```bash
# Analyse statique, depuis la racine du dépôt
ansible-lint --profile production corrige/

# Scénario Molecule, depuis le répertoire du rôle
cd corrige/tp05-roles/roles/nginx
molecule list                  # valide la configuration, sans conteneur
molecule create
molecule converge
molecule verify
molecule test                  # séquence complète, idempotence comprise
molecule destroy
```

## Prérequis Molecule

```bash
pipx install molecule
podman --version               # ou docker, mais podman est la voie documentée
ansible-galaxy collection install containers.podman
```

## Résultats obtenus lors de la rédaction

`molecule list` accepte la configuration et confirme le mode ansible-native :

```
 Instance Name │ Driver Name │ Provisioner Name │ Scenario Name │ Created │ Converged
               │ default     │ ansible          │ default       │ false   │ false
```

La validation du schéma est **stricte**. Une clé inconnue ajoutée à `molecule.yml` produit
immédiatement :

```
ERROR   Failed to validate .../molecule/default/molecule.yml
```

## Images de conteneurs

| Machine | Image | Remarque |
|---|---|---|
| `debian13` | `docker.io/geerlingguy/docker-debian13-ansible:latest` | tag `latest` uniquement |
| `rocky10` | `docker.io/geerlingguy/docker-rockylinux10-ansible:latest` | tag `latest` uniquement |

Ces images embarquent systemd, indispensable pour tester un rôle qui démarre un service.
Les images officielles `debian:trixie` et `rockylinux/rockylinux:10` ne conviennent pas
en l'état ; la variante `rockylinux/rockylinux:10-ubi-init` est l'exception côté Rocky.

> **Validé** sur Ubuntu 26.04, podman 5.7.0 rootless (crun, overlay) : `molecule test`
> complet en 1 min 40 s.
>
> ```
> default ➜ dependency:  Successful
> default ➜ destroy:     Successful
> default ➜ create:      Successful
> default ➜ converge:    Successful   debian13 ok=14 changed=8 / rocky10 ok=11 changed=6
> default ➜ idempotence: Successful   changed=0 sur les deux
> default ➜ verify:      Successful
> default ➜ destroy:     Successful
> default : actions=7  successful=6  failed=0
> ```
