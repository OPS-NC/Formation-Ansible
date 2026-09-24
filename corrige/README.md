# Corrigés

Projet fil rouge de la formation, construit TP par TP. Chaque répertoire correspond
à un travail pratique et contient les fichiers introduits ou modifiés par ce TP.

> 🧵 **Continuité du projet.** Dans votre travail, faites évoluer les mêmes fichiers d'un TP au
> suivant. Les corrigés évitent de tout dupliquer : le TP 03 réutilise par exemple l'inventaire
> du TP 02, et le TP 08 ajoute ses tests au rôle du TP 05. Le README de chaque corrigé précise
> les éléments à reprendre et les sources d'inventaire à charger ensemble.

| TP | Répertoire | Module |
|---|---|---|
| 01 | `tp01-lab/` | [02 — Nœud de contrôle et lab](../J1-Socle/02-Noeud-De-Controle.md) |
| 02 | `tp02-inventaire/` | [03 — Inventaire et commandes ad hoc](../J1-Socle/03-Inventaire.md) |
| 03 | `tp03-playbook-base/` | [04 — Playbooks : fondamentaux](../J1-Socle/04-Playbooks.md) |
| 04 | `tp04-nginx/` | [05 — Variables, Jinja2, handlers](../J1-Socle/05-Variables-Jinja-Handlers.md) |
| 05 | `tp05-roles/` | [06 — Rôles, collections, Galaxy](../J1-Socle/06-Roles-Collections.md) |
| 06 | `tp06-patching/` | [07 — Exécution avancée](../J2-Industrialisation/07-Execution-Avancee.md) |
| 07 | `tp07-inventaire-dynamique/` | [08 — Inventaires dynamiques](../J2-Industrialisation/08-Inventaires-Dynamiques.md) |
| 08 | `tp08-qualite/` | [09 — Qualité : lint et tests](../J2-Industrialisation/09-Qualite.md) |
| 09 | `tp09-cicd/` | [10 — Git et CI/CD](../J2-Industrialisation/10-Git-CICD.md) |
| 10 | `tp10-secrets/` | [11 — Gestion des secrets](../J2-Industrialisation/11-Secrets.md) |
| 11 | `tp11-semaphore/` | [12 — Interfaces web](../J2-Industrialisation/12-WebUI.md) |
| 12 | `tp12-provisioning/` | [13 — Provisioning](../J3-Perimetres-Avances/13-Provisioning.md) |
| 13 | `tp13-reseau/` | [14 — Automatisation réseau](../J3-Perimetres-Avances/14-Reseau.md) |
| 14 | `tp14-k3s/` | [15 — Kubernetes avec Ansible](../J3-Perimetres-Avances/15-Kubernetes.md) |

## Utilisation

Les corrigés sont à consulter **après** avoir cherché. Pour exécuter un corrigé,
placez-vous à la racine du dépôt (les chemins relatifs, notamment les clés SSH
Vagrant, en dépendent) :

```bash
ansible-playbook -i corrige/tp02-inventaire/inventories/dev/hosts.yml \
                 corrige/tp03-playbook-base/playbooks/base.yml --check --diff
```

Tous les corrigés passent `ansible-lint` au profil indiqué dans le module correspondant.
