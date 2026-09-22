# Module 05 — Variables, Jinja2, templates et handlers

> **Jour 1** · 75 min · Théorie + **TP 04**
> Prérequis : [module 04](04-Playbooks.md).

## Objectifs

- Manipuler variables, boucles et conditions sans rendre le playbook illisible.
- Écrire un gabarit Jinja2 maîtrisant les espaces et les valeurs par défaut.
- Utiliser les handlers, y compris leur ordre d'exécution et `flush_handlers`.
- Piloter la configuration **par les données** plutôt que par le code.

---

## 1. Définir des variables

| Emplacement | Usage |
|---|---|
| `group_vars/`, `host_vars/` | Données du parc (module 03) |
| `vars:` du play | Données propres à ce playbook |
| `vars_files:` | Fichier externe, souvent chiffré (module 11) |
| `set_fact` | Valeur calculée pendant l'exécution |
| `register` | Résultat d'une tâche |
| `-e` / `--extra-vars` | Surcharge ponctuelle, priorité maximale |

### `register`

Chaque module renvoie un dictionnaire. Les clés communes sont `changed`, `failed`, `rc`,
`stdout`, `stderr`, `stdout_lines`, `msg`.

```yaml
- name: Relever l espace disque
  ansible.builtin.command: df -h /
  register: disque
  changed_when: false

- name: Afficher la derniere ligne
  ansible.builtin.debug:
    var: disque.stdout_lines[-1]
```

Avec une boucle, `register` collecte une liste dans la clé `results` :

```yaml
- name: Tester plusieurs URL
  ansible.builtin.uri:
    url: "{{ item }}"
  loop: "{{ urls }}"
  register: tests

- name: Compter les echecs
  ansible.builtin.debug:
    msg: "{{ tests.results | selectattr('failed') | list | length }} échec(s)"
```

### `set_fact`

Définit une variable pour la suite du play, sur la machine courante. Sa priorité est élevée :
elle l'emporte sur les variables d'inventaire.

```yaml
- name: Construire le nom complet
  ansible.builtin.set_fact:
    fqdn: "{{ inventory_hostname }}.{{ parc_domaine }}"
```

## 2. Jinja2

### 2.1 Les trois délimiteurs

| Syntaxe | Rôle |
|---|---|
| `{{ ... }}` | Expression — produit du texte |
| `{% ... %}` | Instruction — `if`, `for`, `set` |
| `{# ... #}` | Commentaire — n'apparaît pas dans le résultat |

### 2.2 Filtres indispensables

```jinja
{{ port | default(80) }}                  valeur si non définie
{{ port | default(80, true) }}            valeur si non définie OU vide
{{ mdp | mandatory }}                     échoue explicitement si absente
{{ liste | join(', ') }}                  concaténer
{{ liste | sort | unique }}               trier, dédoublonner
{{ liste | length }}                      taille
{{ dico | dict2items }}                   dictionnaire → liste de {key, value}
{{ liste | map(attribute='nom') | list }} extraire un champ
{{ serveurs | selectattr('actif') | list }}       filtrer
{{ serveurs | rejectattr('nom', 'eq', 'old') | list }}
{{ texte | regex_replace('^v', '') }}     substitution
{{ chemin | basename }} {{ chemin | dirname }}
{{ donnees | to_nice_yaml }} {{ donnees | to_nice_json }}
{{ mdp | password_hash('sha512') }}       empreinte de mot de passe
{{ '192.168.56.0/24' | ansible.utils.ipaddr('net') }}
```

> **Attention**
> `default(valeur)` ne se déclenche que si la variable est **indéfinie**. Une chaîne vide ou
> `false` passe au travers. Pour les couvrir, ajoutez le second argument : `default(80, true)`.

### 2.3 Conditions et boucles

```yaml
- name: Installer un paquet supplementaire en developpement
  ansible.builtin.package:
    name: "{{ paquet_debug }}"
  when:
    - parc_environnement == 'dev'          # une liste = ET logique
    - paquet_debug is defined
```

Tests utiles : `is defined`, `is not defined`, `is none`, `is truthy`, `in`, `is match(...)`,
`is version('2.0', '>=')`.

```yaml
- name: Creer les repertoires
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    mode: "0755"
  loop:
    - /opt/app
    - /opt/app/bin
```

**`loop_control`** rend la sortie lisible et évite les collisions de nom :

```yaml
  loop: "{{ sites }}"
  loop_control:
    loop_var: site        # remplace `item`, indispensable en boucle imbriquée
    label: "{{ site.nom }}"   # n'affiche que le nom, pas le dictionnaire entier
```

Sans `label`, chaque itération affiche le dictionnaire complet et la sortie devient
inexploitable.

**Attente d'une condition** :

```yaml
- name: Attendre que l application reponde
  ansible.builtin.uri:
    url: http://127.0.0.1:8080/health
  register: sante
  until: sante.status == 200
  retries: 12
  delay: 5
```

### 2.4 Maîtriser les espaces

C'est ce qui distingue un gabarit propre d'un fichier truffé de lignes vides. Une instruction
`{% ... %}` sur sa propre ligne laisse un saut de ligne derrière elle.

```jinja
{% for p in ports %}
listen {{ p }};
{% endfor %}
```

Deux corrections possibles :

- **Marqueur `-`** : `{%- ... -%}` supprime les espaces avant ou après le bloc.
  ```jinja
  {% for p in ports -%}
  listen {{ p }};
  {%- endfor %}
  ```
- **Options globales** du module `template` : `trim_blocks` (actif par défaut) et
  `lstrip_blocks` (inactif par défaut).

### 2.5 En-tête `ansible_managed`

Signalez tout fichier généré, pour éviter qu'il soit modifié à la main :

```jinja
{{ ansible_managed | ansible.builtin.comment }}
```

```
#
# Ansible managed
#
```

## 3. Templates

```yaml
- name: Generer la configuration du vhost
  ansible.builtin.template:
    src: vhost.conf.j2
    dest: /etc/nginx/sites-available/site.conf
    owner: root
    group: root
    mode: "0644"
    backup: true
    validate: /usr/sbin/nginx -t -c %s
  notify: recharger nginx
```

`src` est cherché dans `templates/` à côté du playbook, ou dans `templates/` du rôle. Un chemin
relatif n'a donc pas besoin de préfixe.

> **Attention — `validate` n'est pas toujours applicable**
> `validate` n'a de sens que si la commande sait valider **le fichier seul**. C'est le cas de
> `visudo -cf %s` ou `sshd -t -f %s`. Ce n'est **pas** le cas de `nginx -t -c %s` appliqué à un
> fragment de vhost : nginx attend un fichier de configuration complet et refusera un extrait.
> Pour un fragment, validez la configuration globale **après** dépôt, dans un handler.

### `copy` ou `template` ?

`copy` transfère un fichier tel quel ; `template` le rend d'abord. Utilisez `copy` avec
`content:` pour un contenu court et littéral :

```yaml
- name: Autoriser sudo pour le compte de service
  ansible.builtin.copy:
    content: "ansible ALL=(ALL) NOPASSWD:ALL\n"
    dest: /etc/sudoers.d/90-ansible
    mode: "0440"
    validate: /usr/sbin/visudo -cf %s
```

## 4. Handlers

Un handler est une tâche qui ne s'exécute **que si elle est notifiée**, et **une seule fois**
quel que soit le nombre de notifications.

```yaml
  handlers:
    - name: Controler la configuration nginx
      listen: configuration nginx modifiee
      ansible.builtin.command: nginx -t
      changed_when: false

    - name: Recharger nginx
      listen: configuration nginx modifiee
      ansible.builtin.systemd_service:
        name: nginx
        state: reloaded

  tasks:
    - name: Generer le vhost
      ansible.builtin.template:
        src: vhost.conf.j2
        dest: /etc/nginx/sites-available/site.conf
        mode: "0644"
      notify: configuration nginx modifiee
```

### Quatre règles à connaître

1. **La notification n'a lieu que si la tâche est `changed`.** Une tâche `ok` ne notifie rien.
2. **Les handlers s'exécutent à la fin du play**, pas à l'endroit de la notification.
3. **Ils s'exécutent dans l'ordre où ils sont *définis***, jamais dans l'ordre des
   notifications. C'est ce qui permet de garantir ici que le contrôle précède le rechargement.
4. **`listen`** crée un sujet auquel plusieurs handlers s'abonnent. Les tâches notifient le
   sujet, pas chaque handler : on peut ajouter une action sans toucher aux tâches.

### `flush_handlers`

Pour déclencher les handlers en attente au milieu d'un play — typiquement avant de tester que
le service répond :

```yaml
- name: Declencher les handlers en attente
  ansible.builtin.meta: flush_handlers
```

### Le piège de l'échec

Si une tâche ultérieure échoue, **les handlers notifiés ne s'exécutent pas** : la machine reste
avec la nouvelle configuration sur disque et l'ancienne en mémoire. Deux réponses :
`--force-handlers` en ligne de commande, ou `force_handlers: true` dans le play.

## 5. Piloter par les données

C'est la différence entre un playbook qui vieillit bien et un playbook que l'on réécrit.

```yaml
# Piloté par le code : ajouter un site = ajouter des tâches
- name: Deployer le vhost vitrine
  ansible.builtin.template:
    src: vitrine.conf.j2
    dest: /etc/nginx/sites-available/vitrine.conf

- name: Deployer le vhost api
  ansible.builtin.template:
    src: api.conf.j2
    dest: /etc/nginx/sites-available/api.conf
```

```yaml
# Piloté par les données : ajouter un site = ajouter 2 lignes de variables
- name: Deployer les vhosts
  ansible.builtin.template:
    src: vhost.conf.j2
    dest: "/etc/nginx/sites-available/{{ site.nom }}.conf"
    mode: "0644"
  loop: "{{ sites }}"
  loop_control:
    loop_var: site
    label: "{{ site.nom }}"
```

Le gabarit absorbe les variantes par des valeurs par défaut et des conditions :

```jinja
listen {{ site.port | default(http_port) }};
server_name {{ site.nom }}.{{ parc_domaine }}{% if site.alias is defined %} {{ site.alias | join(' ') }}{% endif %};
```

Avec cette entrée :

```yaml
- nom: api
  port: 8080
  alias: [api-v1, api-legacy]
  proxies:
    /v1/: http://127.0.0.1:9001
```

le rendu obtenu est :

```nginx
listen 8080;
server_name api.lab.local api-v1 api-legacy;
...
    location /v1/ {
        proxy_pass http://127.0.0.1:9001;
```

Et sans `port` ni `alias`, le même gabarit produit `listen 80;` et `server_name vitrine.lab.local;`.

---

## TP 04 — Serveurs web pilotés par les données

**Durée : 40 min.** Corrigé : [`corrige/tp04-nginx/`](../corrige/tp04-nginx/)

### Objectif

Déployer plusieurs sites nginx sur `web01` et `web02` à partir d'une **liste de données**, avec
rechargement conditionnel du service.

### Énoncé

Écrire `playbooks/web.yml`, ciblant le groupe `web`, déclarant une variable `sites` contenant
trois entrées :

| Site | Particularité |
|---|---|
| `vitrine` | Aucune — toutes les valeurs par défaut s'appliquent |
| `api` | Port 8080, deux alias, niveau de journalisation `info`, deux `location` de proxy |
| `ancien` | Redirection permanente vers HTTPS, sans bloc `location` |

Le playbook doit :

1. Installer nginx, le démarrer et l'activer au démarrage.
2. Créer la racine documentaire de chaque site sous `site_racine`.
3. Déposer une page d'accueil générée depuis `templates/index.html.j2`, affichant le nom de la
   machine, son adresse, sa distribution et ses groupes.
4. Générer un vhost par site depuis `templates/vhost.conf.j2` dans `sites-available`.
5. Activer chaque vhost par un lien symbolique vers `sites-enabled`.
6. Supprimer le site `default` de Debian.
7. Notifier, pour toute modification de configuration, un sujet `configuration nginx modifiee`
   auquel deux handlers s'abonnent : **contrôle** (`nginx -t`) puis **rechargement**.
8. Déclencher les handlers, puis vérifier que chaque site répond avec `ansible.builtin.uri`.

Le gabarit de vhost doit gérer, par des valeurs par défaut et des conditions : port, alias,
niveau de journalisation, redirection HTTPS, et une liste variable de `location` de proxy.

### Déroulé attendu

```bash
ansible-lint playbooks/
ansible-playbook playbooks/web.yml --check --diff
ansible-playbook playbooks/web.yml
ansible-playbook playbooks/web.yml        # idempotence : changed=0, aucun handler
```

### Vérification

```bash
curl -s http://192.168.56.11/ | head -5
curl -s -H "Host: api.lab.local" http://192.168.56.11:8080/v1/ -o /dev/null -w "%{http_code}\n"
ansible web -a "nginx -t" --become
```

### Points d'attention

- **Pas de `validate: nginx -t -c %s`** sur un fragment de vhost : nginx exige une configuration
  complète. Le contrôle se fait dans le handler.
- Sans `flush_handlers`, la vérification finale interroge un nginx qui n'a pas encore rechargé.
- La page d'accueil ne notifie **pas** : modifier un contenu statique ne justifie pas de
  recharger le service.
- `loop_var: site` évite la collision avec `item` et rend le gabarit lisible.

### Pièges courants

| Symptôme | Cause |
|---|---|
| Handler jamais exécuté | La tâche est `ok`, pas `changed` |
| Handlers exécutés dans le désordre | Confusion : c'est l'ordre de **définition** qui compte |
| `dict object has no attribute 'port'` | `site.port` utilisé sans `default()` |
| Lignes vides dans le fichier généré | Espaces Jinja2 non maîtrisés (`{%-` / `-%}`) |
| Vérification finale en échec | `flush_handlers` manquant |

### Pour aller plus loin

- Ajouter un quatrième site en n'écrivant **que** des données, sans toucher aux tâches.
- Tester un gabarit sans VM : un play `hosts: localhost, connection: local` qui rend le gabarit
  dans `/tmp` avec des variables fictives. C'est la boucle de retour la plus rapide pour mettre
  au point du Jinja2.
- Provoquer un échec après la notification et constater que le handler ne s'exécute pas, puis
  relancer avec `--force-handlers`.

---

## Points clés

- `default(x)` ne couvre pas la chaîne vide : utilisez `default(x, true)`.
- `loop_control.label` et `loop_var` sont obligatoires dès que l'on boucle sur des dictionnaires.
- Un handler ne part **que sur `changed`**, s'exécute **à la fin du play**, **une seule fois**,
  et **dans l'ordre de définition**.
- `listen` découple les tâches des handlers ; `flush_handlers` force leur exécution.
- En cas d'échec ultérieur, les handlers sont perdus : `force_handlers: true`.
- `validate` ne s'applique qu'aux fichiers validables seuls — pas à un fragment de vhost.
- **Pilotez par les données** : ajouter un élément doit se faire en ajoutant des variables,
  pas des tâches.

---

**Module précédent :** [04 — Playbooks : fondamentaux](04-Playbooks.md)
**Module suivant :** [06 — Rôles, collections, Galaxy](06-Roles-Collections.md)
