# Module 07 — Exécution avancée

> **Jour 2** · 75 min · Théorie + **TP 06**
> Prérequis : [module 06](../J1-Socle/06-Roles-Collections.md).

## Objectifs

- Traiter les erreurs sans laisser le parc dans un état intermédiaire.
- Orchestrer une opération par vagues sur un parc en production.
- Déléguer une tâche à une autre machine que la cible.
- Choisir une stratégie d'exécution et diagnostiquer les lenteurs.

---

## 1. Traitement des erreurs

Par défaut, une tâche en échec retire la machine du play. Les autres continuent. Ce
comportement convient pour une configuration, pas pour une opération qui laisse le système dans
un état transitoire — une mise à jour, une migration, une bascule.

### `block` / `rescue` / `always`

```yaml
- name: Operation de mise a jour
  block:
    - name: Sortir la machine de la rotation
      ...
    - name: Mettre a jour les paquets
      ...
  rescue:
    # Uniquement si une tâche du block a échoué
    - name: Tracer l echec
      ...
  always:
    # Dans tous les cas
    - name: Remettre la machine en rotation
      ...
```

Points à retenir :

- Une erreur rattrapée par `rescue` est comptée `rescued`, et **la machine reste dans le play**.
- `always` s'exécute même si `rescue` échoue à son tour. C'est là que vont les remises en état.
- Les blocs acceptent `when`, `become`, `tags` : ils s'appliquent à toutes les tâches du bloc.
- `ansible_failed_task` et `ansible_failed_result` sont disponibles dans `rescue`.

> **Traiter l'erreur ne l'annule pas.** `rescue` ne restaure pas les paquets précédents :
> un retour arrière doit être écrit explicitement. Si `rescue` réussit, Ansible considère
> l'erreur comme traitée ; le TP utilise donc `fail` dans `rescue` pour arrêter les lots suivants.
> Une machine devenue `UNREACHABLE` ne déclenche pas ces blocs comme un échec de tâche :
> `always` ne garantit pas un nettoyage distant si la connexion est perdue.

### Les modificateurs d'échec

| Directive | Effet |
|---|---|
| `ignore_errors: true` | Poursuit malgré l'échec. À éviter : masque les vrais problèmes. |
| `ignore_unreachable: true` | Poursuit si la machine est injoignable |
| `failed_when: <expr>` | Redéfinit **entièrement** la condition d'échec |
| `any_errors_fatal: true` | Un échec sur **une** machine arrête **toutes** les machines |
| `max_fail_percentage: N` | Arrête si plus de N % des machines ont échoué |
| `force_handlers: true` | Exécute les handlers notifiés malgré un échec ultérieur |

```yaml
- name: Verifier l espace disque
  ansible.builtin.command: df --output=pcent /
  register: disque
  changed_when: false
  failed_when: disque.stdout_lines[-1] | regex_replace('[^0-9]', '') | int > 90
```

> **Attention**
> `failed_when` **remplace** le test par défaut sur le code retour. Si votre expression ne
> couvre pas `rc != 0`, une commande qui plante sera considérée comme réussie.

## 2. Orchestrer par vagues

### `serial`

Par défaut, Ansible traite toutes les machines de front (par lots de `forks`). Sur un parc en
production, c'est exactement ce qu'il ne faut pas faire.

```yaml
serial: 1                 # une machine à la fois
serial: [1, 5, 10]        # canari, puis 5, puis 10
serial: "25%"             # par quarts
```

`serial` découpe le play en sous-plays successifs : chaque lot traverse **toutes** les tâches
avant que le suivant ne démarre. Les handlers sont donc déclenchés **par lot**.

> `forks` limite le nombre de tâches exécutées en parallèle ; `serial` limite le nombre
> de machines engagées dans **tout le cycle** de maintenance. Avec `forks = 1` seul, chaque
> machine pourrait être mise en maintenance avant que la première soit rétablie. Avec
> `serial: 1`, la première termine le cycle avant que la suivante le commence.

### `max_fail_percentage` et `any_errors_fatal`

Avec `serial`, ces directives prennent tout leur sens : `max_fail_percentage: 0` arrête le
déploiement dès le premier lot en échec, ce qui préserve le reste du parc.

```yaml
serial: 1
max_fail_percentage: 0
```

### `run_once`

Exécute la tâche sur la **première** machine du lot, et diffuse le résultat aux autres.

```yaml
- name: Appliquer la migration de schema
  ansible.builtin.command: /opt/app/bin/migrate
  run_once: true
```

> **Attention**
> Avec `serial`, `run_once` s'applique **par lot**, pas une fois pour tout le play.

## 3. Délégation

`delegate_to` exécute une tâche **sur une autre machine** que la cible, tout en conservant le
contexte de la cible (ses variables, ses facts).

```yaml
- name: Retirer le serveur du repartiteur de charge
  community.general.haproxy:
    state: disabled
    host: "{{ inventory_hostname }}"
  delegate_to: lb01

- name: Ecrire le rapport
  ansible.builtin.copy:
    content: "{{ rapport | to_nice_json }}"
    dest: ./rapport.json
    mode: "0644"
  run_once: true
  delegate_to: localhost
  become: false
```

Le couple `run_once: true` + `delegate_to: localhost` est l'idiome standard pour produire un
rapport consolidé : une seule exécution, sur le nœud de contrôle.

> `become: false` est presque toujours nécessaire sur une délégation vers `localhost` : sinon
> Ansible tente un `sudo` sur votre poste.

`delegate_facts: true` enregistre les facts collectés au nom de la **machine déléguée** et non
de la cible.

### Autres directives de placement

| Directive | Effet |
|---|---|
| `connection: local` | La tâche s'exécute sur le contrôleur, sans SSH |
| `throttle: N` | Au plus N exécutions simultanées pour cette tâche |
| `order` | Ordre de parcours : `inventory`, `sorted`, `reverse_sorted`, `shuffle` |

## 4. Stratégies et performance

| Stratégie | Comportement |
|---|---|
| `linear` (défaut) | Barrière après chaque tâche : toutes les machines terminent avant la suivante |
| `free` | Chaque machine avance à son rythme, sans attendre les autres |
| `host_pinned` | Une machine occupe un *fork* jusqu'à la fin de son play |
| `debug` | Ouvre un débogueur interactif en cas d'échec |

`free` accélère un parc hétérogène, mais retire toute garantie d'ordre entre machines : à
proscrire dès qu'il existe une dépendance entre elles.

### Les leviers de performance

1. **`forks`** — le plus efficace. La valeur par défaut, 5, est très basse. Elle est limitée par
   la mémoire et le nombre de descripteurs de fichiers du contrôleur.
2. **`pipelining = true`** — réduit le nombre d'opérations SSH par tâche.
3. **`ControlPersist`** — réutilisation des connexions SSH, déjà dans `ssh_args`.
4. **Réduire les facts** — `gather_facts: false`, `gather_subset`, ou cache de facts (module 08).

Mesurer avant d'optimiser, avec les callbacks déjà activés dans `ansible.cfg` :

```console
TASK [base : Installer les paquets de base] ************************************
Tuesday 22 September 2026  09:14:02 +1100 (0:00:03.417)       0:00:12.884

Tuesday 22 September 2026  09:14:05 +1100 (0:00:02.203)
===============================================================================
base : Installer les paquets de base ----------------------------------- 3.42s
Gathering Facts -------------------------------------------------------- 2.20s
```

## 5. Tâches longues

```yaml
- name: Lancer une sauvegarde longue
  ansible.builtin.command: /opt/backup.sh
  async: 3600      # durée maximale
  poll: 0          # 0 = ne pas attendre
  register: sauvegarde

- name: ... autres tâches pendant ce temps ...

- name: Attendre la fin de la sauvegarde
  ansible.builtin.async_status:
    jid: "{{ sauvegarde.ansible_job_id }}"
  register: etat
  until: etat.finished
  retries: 120
  delay: 30
```

`poll: 0` détache la tâche. Avec `poll: N`, Ansible attend en interrogeant toutes les N
secondes — utile pour dépasser le délai d'expiration SSH sans détacher.

## 6. Redémarrer proprement

```yaml
- name: Redemarrer la machine
  ansible.builtin.reboot:
    reboot_timeout: 300
    test_command: /usr/bin/true
```

Le module `reboot` redémarre **et attend** le retour de la machine. Pour un contrôle plus fin :

```yaml
- name: Demander le redemarrage
  ansible.builtin.shell: sleep 2 && systemctl reboot
  async: 1
  poll: 0
  changed_when: true

- name: Attendre le retour du service SSH
  ansible.builtin.wait_for_connection:
    delay: 15
    timeout: 300
```

## 7. Tags

```yaml
- name: Installer les paquets
  ansible.builtin.package:
    name: "{{ paquets_base }}"
  tags: [paquets, base]
```

```bash
ansible-playbook site.yml --tags paquets
ansible-playbook site.yml --skip-tags reboot
ansible-playbook site.yml --list-tags
```

Tags spéciaux : `always` (toujours exécuté, sauf `--skip-tags`), `never` (jamais, sauf appel
explicite).

> **Attention**
> Les tags ne se propagent pas dans un `include_*` : il faut `apply: { tags: [...] }`. Avec
> `import_*`, la propagation est automatique. C'est la principale différence pratique entre les
> deux.

---

## TP 06 — Mise à jour orchestrée du parc

**Durée : 35 min.** Corrigé : [`corrige/tp06-patching/`](../corrige/tp06-patching/)

### Objectif

Mettre à jour les serveurs **un par un**, en les sortant de la rotation, avec remise en rotation
conditionnée au contrôle de santé et rapport consolidé.

### Énoncé

Écrire `playbooks/patching.yml` ciblant le groupe `serveurs`, avec `serial: 1` et
`max_fail_percentage: 0`.

> **Attention — un paquet peut poser une question.** `grub-pc` redemande son disque
> d'installation à chaque mise à jour, et la box Debian du lab ne porte aucune réponse
> enregistrée. En mode non interactif, `apt` s'arrête sur
> `dpkg: error processing package grub-pc (--configure)`. La réponse doit être enregistrée
> dans debconf **avant** la mise à jour (`ansible.builtin.debconf`).

Dans un `block` :

1. Déposer un fichier `MAINTENANCE` dans la racine web (uniquement pour les machines du groupe
   `web`). **Ce fichier est un témoin** : aucun répartiteur du lab ne le consulte. En production,
   il faut le relier à la sonde de santé pour que la sortie de rotation soit réelle.
2. Mettre à jour **tous** les paquets.
3. Déterminer si un redémarrage est nécessaire. Le mécanisme diffère : comparaison du noyau
   en cours d'exécution au plus récent noyau installé sur Debian, code retour de
   `dnf needs-restarting -r` sur Rocky. Porter la commande **et le code retour attendu** dans
   les variables de groupe, puis normaliser le résultat dans une variable unique.

   > **Attention** — `/var/run/reboot-required` est un mécanisme **Ubuntu**. Il est déposé par
   > le crochet apt de `update-notifier-common`, paquet qui n'existe pas dans Debian 13 : sur
   > `bento/debian-13` ce fichier n'apparaît jamais et le test répondrait toujours « aucun
   > redémarrage nécessaire ».
4. Redémarrer si nécessaire, et attendre le retour de la machine.
5. Vérifier que le service web répond, avec `until` / `retries`.

Dans `rescue` : tracer l'échec et interrompre le déploiement.
Dans `always` : retirer le fichier `MAINTENANCE`, **uniquement si la vérification a réussi**.

Ajouter un second play produisant `rapport-patching.json` sur le **nœud de contrôle**, indiquant
pour chaque machine si un redémarrage a été nécessaire.

> **Lire le résultat.** Le second play n'a pas de `serial` : son `run_once` produit un seul
> rapport, après les lots. Avec `--limit`, ce rapport porte seulement sur les hôtes retenus.
> La simulation ne permet pas de prédire si de nouveaux paquets imposeront un redémarrage :
> ils ne sont pas installés. Enfin, ce playbook réalise une opération de maintenance ; le
> témoin temporaire et le rapport daté peuvent changer à chaque passage, même sans mise à jour.

### Déroulé attendu

```bash
ansible-playbook playbooks/patching.yml --check --diff
ansible-playbook playbooks/patching.yml
cat rapport-patching.json
```

```json
{
    "date": "2026-09-22T09:14:11.695319",
    "redemarrage_requis": {
        "db01": false,
        "web01": true,
        "web02": false
    }
}
```

### Points d'attention

- **Deux exceptions assumées** à la règle du module 04, pour la même raison. La mise à jour
  complète d'un système n'est pas portable : `dnf` accepte `name: '*'` avec `state: latest`,
  là où `apt` attend `upgrade: dist`. La détection du redémarrage diffère de même. Quand deux
  familles diffèrent par une **valeur**, les variables de groupe suffisent. Quand elles diffèrent
  par le **mécanisme** — ici deux commandes de diagnostic différentes — il faut normaliser explicitement.
  La règle reste : ne pas laisser la différence se propager dans la suite du playbook.
- `serial: 1` transforme le play en une succession de sous-plays. Les handlers sont déclenchés
  **par machine**, pas en fin de parcours.
- `always` s'exécute même après un `rescue`. Conditionnez la remise en rotation sur la réussite
  réelle du contrôle, sinon une machine en panne est remise en service.
- `run_once` + `delegate_to: localhost` + `become: false` : les trois vont ensemble.
- Le dossier partagé `/vagrant` est désactivé dans le lab, ce qui évite qu'une mise à jour du
  noyau sur Rocky ne casse le montage `vboxsf` au redémarrage suivant.

### Pièges courants

| Symptôme | Cause |
|---|---|
| Le parc entier tombe | `serial` absent |
| Le déploiement continue après un échec | `max_fail_percentage` absent |
| `MAINTENANCE` persiste après échec | Attendu si le contrôle de santé n'a pas réussi : la machine reste signalée en maintenance |
| Machine en panne remise en rotation | `always` non conditionné sur la réussite |
| `sudo: a password is required` sur le rapport | `become: false` oublié sur la délégation |
| Rapport écrit autant de fois qu'il y a de machines | `run_once` oublié |

### Pour aller plus loin

- Passer en `serial: [1, 2]` et observer le lot canari.
- Faire échouer volontairement la vérification finale (arrêter nginx sur `web02` juste avant) et
  constater le déclenchement de `rescue` puis de `always`.
- Comparer les durées entre `strategy: linear` et `strategy: free`.
- Mesurer l'effet de `forks = 10` puis `forks = 2` avec le callback `profile_tasks`.

---

## Points clés

- `block` / `rescue` / `always` : `always` est le seul endroit fiable pour la remise en état.
- `failed_when` **remplace** le test sur le code retour.
- `serial` + `max_fail_percentage: 0` : la combinaison qui protège un parc en production.
- `run_once` s'applique **par lot** quand `serial` est utilisé.
- `run_once` + `delegate_to: localhost` + `become: false` = rapport consolidé.
- `forks` est le premier levier de performance ; mesurez avec `profile_tasks`.
- Les tags se propagent avec `import_*`, pas avec `include_*`.

---

**Module précédent :** [06 — Rôles, collections, Galaxy](../J1-Socle/06-Roles-Collections.md)
**Module suivant :** [08 — Inventaires dynamiques](08-Inventaires-Dynamiques.md)
