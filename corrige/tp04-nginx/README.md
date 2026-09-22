# TP 04 — Serveurs web pilotés par les données

Énoncé : [module 05](../../J1-Socle/05-Variables-Jinja-Handlers.md#tp-04--serveurs-web-pilotés-par-les-données)

## Contenu

```
playbooks/
├── web.yml                    9 tâches, 2 handlers abonnés à un sujet commun
└── templates/
    ├── vhost.conf.j2          vhost nginx paramétrable
    └── index.html.j2          page d'accueil avec facts et variables d'inventaire
```

Réutilise l'inventaire du [TP 02](../tp02-inventaire/). Le play ne cible que le groupe `web`
(machines Debian), les chemins `sites-available` / `sites-enabled` étant propres à Debian.

## Vérification

```bash
I=corrige/tp02-inventaire/inventories/dev/hosts.yml
P=corrige/tp04-nginx/playbooks/web.yml

ansible-lint corrige/tp04-nginx/
ansible-playbook -i $I $P --check --diff
ansible-playbook -i $I $P
ansible-playbook -i $I $P          # idempotence : changed=0
curl -s http://192.168.56.11/ | head -5
```

## Les trois sites et ce qu'ils démontrent

| Site | Données fournies | Rendu obtenu |
|---|---|---|
| `vitrine` | `nom`, `titre` | `listen 80`, `server_name vitrine.lab.local`, log `warn` |
| `api` | `port`, `alias`, `log_level`, `proxies` | `listen 8080`, deux alias, log `info`, deux blocs `location` de proxy |
| `ancien` | `https_redirect: true` | `return 301`, aucun bloc `location` |

Un seul gabarit produit les trois. Ajouter un site consiste à ajouter une entrée dans `sites`.

## Techniques illustrées

| Technique | Emplacement |
|---|---|
| Boucle sur des dictionnaires, `loop_var` et `label` | toutes les tâches en boucle |
| Valeurs par défaut dans le gabarit | `site.port \| default(http_port)` |
| Bloc conditionnel | `{% if site.https_redirect %}` |
| Boucle sur un dictionnaire dans un gabarit | `site.proxies \| default({})` |
| Deux handlers sur un sujet commun (`listen`) | contrôle puis rechargement |
| Ordre d'exécution des handlers | défini par l'ordre de déclaration |
| Déclenchement anticipé | `meta: flush_handlers` |
| Pas de notification pour du contenu statique | dépôt de `index.html` |
