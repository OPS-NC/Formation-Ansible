# Module 04 — Playbooks : fondamentaux

> **Jour 1** · 75 min · Théorie + **TP 03**
> Prérequis : [module 03](03-Inventaire.md), inventaire structuré en place.

## Objectifs

- Écrire un playbook lisible et rejouable sur deux familles de distributions.
- Choisir le bon module et l'encadrer pour qu'il soit idempotent.
- Exploiter les facts.
- Valider un changement avant de l'appliquer avec `--check` et `--diff`.

---

## 1. Anatomie d'un playbook

Un playbook est une **liste de plays**. Un play associe un motif d'hôtes à une liste de tâches.

```yaml
---
- name: Configuration de base du parc      # nom du play
  hosts: all                               # motif (module 03)
  become: true                             # élévation de privilèges
  gather_facts: true                       # collecte des facts (défaut)

  vars:
    admin_user: ansible

  tasks:
    - name: Installer les paquets de base  # nom de la tâche
      ansible.builtin.package:             # module, en FQCN
        name: "{{ paquets_base }}"         # paramètres
        state: present
```

Trois règles de forme, toutes vérifiées par `ansible-lint` :

1. **Chaque play et chaque tâche porte un `name`.** C'est ce qui s'affiche à l'exécution et
   dans les journaux. Un playbook sans noms est indébogable.
2. **Les modules sont appelés par leur FQCN.** `package` fonctionne encore, mais `ansible.builtin.package`
   est sans ambiguïté et résiste à l'ajout d'une collection qui définirait le même nom.
3. **Le YAML est indenté à deux espaces, sans tabulation.**

### Ordre d'exécution

Les tâches s'exécutent **dans l'ordre d'écriture**, tâche par tâche, sur toutes les machines en
parallèle (par lots de `forks`), avant de passer à la suivante. Cette barrière implicite entre
tâches est importante : elle garantit qu'à la tâche *n+1*, la tâche *n* est terminée partout.

```
            web01    web02    db01
tâche 1  →    ✓        ✓        ✓     ← barrière
tâche 2  →    ✓        ✓        ✓     ← barrière
tâche 3  →    ✓        ✓        ✓
```

Le module 07 montre comment lever cette barrière (`strategy: free`) ou la resserrer
(`serial`).

## 2. Les modules essentiels

| Besoin | Module | Notes |
|---|---|---|
| Paquets, toutes familles | `ansible.builtin.package` | Délègue à `apt` ou `dnf` |
| Paquets, spécifique | `ansible.builtin.apt`, `ansible.builtin.dnf` | Options fines (cache, `autoremove`) |
| Service | `ansible.builtin.systemd_service` | `state`, `enabled`, `daemon_reload` |
| Copier un fichier | `ansible.builtin.copy` | `content:` pour un contenu littéral |
| Fichier depuis un gabarit | `ansible.builtin.template` | Rendu Jinja2 (module 05) |
| Répertoire, droits, lien | `ansible.builtin.file` | `state: directory`, `absent`, `link`, `touch` |
| Une ligne dans un fichier | `ansible.builtin.lineinfile` | `regexp` + `line` |
| Un bloc dans un fichier | `ansible.builtin.blockinfile` | Encadré par des marqueurs |
| Utilisateur, groupe | `ansible.builtin.user`, `ansible.builtin.group` | |
| Clé SSH autorisée | `ansible.posix.authorized_key` | Collection `ansible.posix` |
| Télécharger | `ansible.builtin.get_url` | `checksum:` recommandé |
| Archive | `ansible.builtin.unarchive` | |
| Dépôt Git | `ansible.builtin.git` | |
| Fuseau horaire | `community.general.timezone` | Collection `community.general` |
| Commande | `ansible.builtin.command`, `.shell` | En dernier recours |

`ansible-doc` donne les options de la version installée :

```bash
ansible-doc ansible.builtin.user          # documentation complète
ansible-doc -s ansible.builtin.user       # aide-mémoire des options
```

> **Attention**
> `ansible.builtin.apt_key` et `ansible.builtin.apt_repository` sont **dépréciés**. Pour ajouter
> un dépôt APT, utilisez `ansible.builtin.deb822_repository`.

## 3. Idempotence

### 3.1 Les états rapportés

| État | Signification |
|---|---|
| `ok` | La cible était déjà conforme, rien n'a été fait |
| `changed` | Le module a modifié quelque chose |
| `skipped` | La condition `when` était fausse |
| `failed` | Erreur |
| `rescued` / `ignored` | Erreur traitée (module 07) |

Le test d'idempotence est simple : **exécuter deux fois, et n'obtenir aucun `changed` au second
passage.** Il sera automatisé par Molecule au module 09.

### 3.2 Encadrer `command` et `shell`

Ces deux modules rapportent `changed` à chaque exécution : Ansible ne peut pas savoir ce qu'une
commande arbitraire a fait. Trois outils pour corriger cela.

**`creates` / `removes`** — la tâche est ignorée si le fichier existe (ou n'existe pas) :

```yaml
- name: Extraire l archive applicative
  ansible.builtin.command: tar -xzf /tmp/app.tar.gz -C /opt/app
  args:
    creates: /opt/app/bin/app       # si ce fichier existe, on ne fait rien
```

**`changed_when: false`** — pour une commande de lecture pure :

```yaml
- name: Relever la version du noyau
  ansible.builtin.command: uname -r
  register: noyau
  changed_when: false
```

**`changed_when` conditionnel** — quand la commande indique elle-même ce qu'elle a fait :

```yaml
- name: Appliquer la configuration applicative
  ansible.builtin.command: /opt/app/bin/reload-config
  register: reload
  changed_when: "'configuration updated' in reload.stdout"
  failed_when: reload.rc not in [0, 2]
```

> **Attention**
> Par défaut, une tâche échoue si le code retour est différent de zéro. `failed_when` remplace
> entièrement ce test : si vous l'utilisez, pensez à y inclure le cas d'erreur réel.

### 3.3 Chercher le module avant d'écrire une commande

Avant d'écrire `shell: systemctl restart nginx`, cherchez le module. Le module apporte
l'idempotence, la gestion du mode simulation, un rapport d'erreur exploitable et la portabilité
entre distributions. La règle `command-instead-of-module` d'`ansible-lint` signale les cas les
plus fréquents.

## 4. Les facts

Avant la première tâche, Ansible exécute `ansible.builtin.setup` sur chaque cible et en récupère
plusieurs centaines de variables.

```bash
ansible web01 -m ansible.builtin.setup | less
ansible web01 -m ansible.builtin.setup -a "filter=ansible_distribution*"
```

Les facts les plus utilisés :

| Fact | Exemple |
|---|---|
| `ansible_facts['distribution']` | `Debian`, `Rocky` |
| `ansible_facts['distribution_major_version']` | `13`, `10` |
| `ansible_facts['os_family']` | `Debian`, `RedHat` |
| `ansible_facts['default_ipv4']['address']` | Adresse de la route par défaut |
| `ansible_facts['<interface>']['ipv4']['address']` | Adresse d'une interface précise |
| `ansible_facts['memtotal_mb']`, `['processor_vcpus']` | Ressources |
| `ansible_facts['python_version']` | Version de l'interpréteur utilisé |
| `ansible_facts['service_mgr']` | `systemd` |

> **Attention**
> Dans un lab Vagrant/VirtualBox, `ansible_facts['default_ipv4']` désigne l'interface **NAT**
> (10.0.2.15), identique sur toutes les VMs. Ne l'utilisez jamais pour identifier une machine
> du réseau host-only. Ce piège fait échouer silencieusement un cluster Kubernetes ; il est
> traité au module 15.

**Coût.** La collecte prend une à plusieurs secondes par machine. Si un play n'en a pas besoin,
`gather_facts: false` le supprime. Pour n'en collecter qu'une partie :

```yaml
gather_facts: true
gather_subset:
  - "!all"
  - network
```

Les facts peuvent aussi être mis en cache entre exécutions (module 08).

### Facts personnalisés

Un fichier `.fact` déposé dans `/etc/ansible/facts.d/` sur la cible est remonté sous
`ansible_facts['ansible_local']`. Format INI ou JSON, ou script exécutable produisant du JSON.

## 5. Vérifier avant d'appliquer

### `--check` : le mode simulation

```bash
ansible-playbook playbooks/base.yml --check
```

Les modules ne modifient rien et rapportent ce qu'ils **auraient** fait. Limites à connaître :

- `command` et `shell` sont **ignorés** en mode simulation, sauf `check_mode: false` explicite.
- Une tâche dépendant du résultat d'une tâche non exécutée peut échouer. C'est normal et attendu.
- `check_mode: false` sur une tâche de lecture la force à s'exécuter même en simulation, ce qui
  rend le reste du playbook simulable.

### `--diff` : montrer le changement

```bash
ansible-playbook playbooks/base.yml --check --diff
```

Affiche le différentiel des fichiers modifiés par `copy`, `template`, `lineinfile`. **Le couple
`--check --diff` est le réflexe à acquérir** : il transforme un playbook en outil d'audit de
conformité, exécutable sans risque en production.

> `--diff` affiche le contenu des fichiers. Sur une tâche manipulant un secret, ajoutez
> `no_log: true` (module 11).

### Autres options de contrôle

```bash
ansible-playbook base.yml --syntax-check     # analyse syntaxique, sans connexion
ansible-playbook base.yml --list-tasks       # liste les tâches
ansible-playbook base.yml --list-hosts       # liste les machines ciblées
ansible-playbook base.yml --start-at-task "Installer les paquets de base"
ansible-playbook base.yml --step             # confirmation avant chaque tâche
ansible-playbook base.yml -v                 # -vvv pour voir les commandes SSH
```

## 6. Traiter deux familles de distributions

L'approche naïve multiplie les conditions :

```yaml
# À éviter
- name: Installer le service NTP
  ansible.builtin.apt:
    name: systemd-timesyncd
  when: ansible_facts['os_family'] == 'Debian'

- name: Installer le service NTP (RedHat)
  ansible.builtin.dnf:
    name: chrony
  when: ansible_facts['os_family'] == 'RedHat'
```

L'approche recommandée place la différence dans les **variables de groupe** (module 03) et garde
une tâche unique :

```yaml
# group_vars/debian.yml → paquet_ntp: systemd-timesyncd, service_ntp: systemd-timesyncd
# group_vars/rocky.yml  → paquet_ntp: chrony,            service_ntp: chronyd

- name: Installer le service de synchronisation horaire
  ansible.builtin.package:
    name: "{{ paquet_ntp }}"
    state: present

- name: Activer le service de synchronisation horaire
  ansible.builtin.systemd_service:
    name: "{{ service_ntp }}"
    state: started
    enabled: true
```

Bénéfices : une seule tâche à maintenir, une lecture qui reste linéaire, et l'ajout d'une
troisième distribution se réduit à un nouveau fichier de variables.

---

## TP 03 — Premier playbook multi-OS

**Durée : 35 min.** Corrigé : [`corrige/tp03-playbook-base/`](../corrige/tp03-playbook-base/)

### Objectif

Écrire un playbook de configuration de base appliqué à l'identique sur Debian 13 et Rocky 10,
et vérifier son idempotence.

### Préparation

```bash
# Collections utilisées par le playbook
ansible-galaxy collection install -r collections/requirements.yml

# Clé SSH du poste de travail, déployée par le playbook
ssh-keygen -t ed25519 -C "formation-ansible" -f ~/.ssh/id_ed25519 -N ""
```

### Énoncé

Écrire `playbooks/base.yml`, appliqué à `all`, avec élévation de privilèges, réalisant :

1. **Nom d'hôte** conforme à `inventory_hostname`.
2. **`/etc/hosts`** généré depuis un gabarit `templates/hosts.j2` contenant **toutes** les
   machines du parc, construit à partir de `groups['all']` et `hostvars`. Sauvegarder le fichier
   existant.
3. **Fuseau horaire** défini à partir de la variable `parc_timezone`.
4. **Paquets de base** installés depuis `paquets_base`, augmentés du paquet NTP de la famille.
5. **Service de synchronisation horaire** démarré et activé au démarrage.
6. **Compte de service `ansible`** avec répertoire personnel et shell.
7. **Clé publique du poste** déposée pour ce compte, uniquement si elle existe sur le
   nœud de contrôle.
8. **Droit `sudo` sans mot de passe** pour ce compte, via un fichier dans `/etc/sudoers.d/`,
   **validé par `visudo` avant mise en place**.
9. **Version du noyau** relevée par une commande, sans que la tâche soit rapportée `changed`.
10. **Résumé** affiché par machine : distribution, version, noyau, version de Python.

### Déroulé attendu

```bash
# 1. Analyse statique, sans aucune connexion
ansible-playbook playbooks/base.yml --syntax-check
ansible-lint playbooks/

# 2. Application
ansible-playbook playbooks/base.yml

# 3. Test d'idempotence : aucun `changed` attendu
ansible-playbook playbooks/base.yml

# 4. Audit de conformité, sur une machine désormais convergée
ansible-playbook playbooks/base.yml --check --diff
```

> **Attention — l'ordre n'est pas interchangeable**
> Sur une machine **vierge**, `--check` ne peut pas valider l'ensemble du playbook. Les paquets
> ne sont pas installés et le compte de service n'est pas créé : les tâches suivantes portent
> alors sur un service ou un utilisateur qui n'existe pas, et échouent. C'est une limite connue
> du mode simulation, pas un défaut du playbook.
>
> La simulation prend tout son sens **après** la première convergence : elle devient un audit de
> dérive, exécutable sans risque et aussi souvent qu'on le souhaite. C'est l'usage retenu dans
> la chaîne d'intégration du module 10.

### Résultat attendu

Au second passage :

```console
PLAY RECAP *********************************************************************
db01  : ok=12   changed=0    unreachable=0    failed=0    skipped=0
tools : ok=12   changed=0    unreachable=0    failed=0    skipped=0
web01 : ok=12   changed=0    unreachable=0    failed=0    skipped=0
web02 : ok=12   changed=0    unreachable=0    failed=0    skipped=0
```

Soit les 11 tâches du playbook plus la collecte des facts. Si la clé publique n'a pas été
générée, la tâche de dépôt est ignorée : `ok=11 skipped=1`.

### Points d'attention

- Le `lookup` qui lit la clé publique s'exécute sur le **nœud de contrôle**, pas sur la cible.
  C'est le cas de tous les lookups.
- `validate: /usr/sbin/visudo -cf %s` fait contrôler le fichier **avant** sa mise en place.
  Sans cela, une erreur de syntaxe rend `sudo` inutilisable sur la machine.
- `hostvars[h]['ansible_host']` fonctionne sans facts : c'est une variable d'inventaire.

### Pièges courants

| Symptôme | Cause |
|---|---|
| `changed` au second passage sur la tâche `command` | `changed_when: false` oublié |
| `Could not find or access 'hosts.j2'` | Gabarit hors de `templates/`, à côté du playbook |
| `The task includes an option with an undefined variable` | Variable de groupe absente pour une famille |
| `sudo: parse error in /etc/sudoers.d/...` | `validate` non utilisé |
| Tâches ignorées en `--check` | Comportement normal de `command` et `shell` |
| Échec en `--check` sur une machine vierge | Attendu : simuler après la première convergence |

### Pour aller plus loin

- Ajouter `--limit rocky` puis `--limit debian` et comparer les paquets installés.
- Modifier `/etc/hosts` à la main sur `web02`, puis relancer en `--check --diff` : le
  différentiel affiché est la dérive détectée.
- Ajouter `-vvv` et retrouver, dans la trace, le module Python transféré sur la cible.

---

## Points clés

- Un playbook est une **liste de plays** exécutée **dans l'ordre**, avec une barrière entre
  chaque tâche.
- **Nom obligatoire** sur chaque play et chaque tâche, **FQCN** sur chaque module.
- `command` et `shell` ne sont pas idempotents : encadrez-les avec `creates`, `removes` ou
  `changed_when`.
- **`--check --diff` est le réflexe** : auditer avant d'appliquer.
- En mode simulation, `command` et `shell` sont **ignorés** sauf `check_mode: false`.
- Les différences entre distributions vont dans les **variables de groupe**, pas dans des `when`.
- `ansible_facts['default_ipv4']` désigne le NAT sous VirtualBox : ne pas s'en servir pour
  identifier une machine.

---

**Module précédent :** [03 — Inventaire et commandes ad hoc](03-Inventaire.md)
**Module suivant :** [05 — Variables, Jinja2, handlers](05-Variables-Jinja-Handlers.md)
