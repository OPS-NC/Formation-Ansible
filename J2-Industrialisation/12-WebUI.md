# Module 12 — Interfaces web

> **Jour 2** · 60 min · Théorie + **TP 11**
> Prérequis : [module 11](11-Secrets.md).

## 🎯 Objectifs

- Savoir ce qu'apporte une interface web par rapport à la ligne de commande.
- Choisir entre les solutions disponibles en 2026, gratuites et payantes.
- Déployer Semaphore UI par Ansible et l'intégrer à Git.

---

## 1. Pourquoi une interface web

La ligne de commande suffit tant qu'une seule personne exploite le parc. Elle atteint ses
limites dès que l'on veut :

| Besoin | Ce que la ligne de commande ne fournit pas |
|---|---|
| **Traçabilité** | Qui a lancé quoi, quand, avec quel résultat |
| **Droits** | Qui a le droit de toucher à la production |
| **Secrets** | Des identifiants centralisés, non copiés sur les postes |
| **Planification** | Une exécution récurrente sans cron sur un poste |
| **Self-service** | Un bouton pour une équipe qui n'écrit pas d'Ansible |
| **Déclenchement** | Une exécution sur événement Git ou sur alerte |

Une interface web n'apporte **aucune** capacité nouvelle à Ansible. Elle apporte de
l'exploitation : contrôle d'accès, journal, ordonnancement.

## 2. Le paysage en 2026

### 🧊 AWX — projet gelé

**AWX 24.6.1, juillet 2024.** Aucune publication depuis plus de deux ans. Le dépôt annonce une
pause pendant une refonte de grande ampleur. Conséquences :

- Déploiement **uniquement** par l'opérateur Kubernetes depuis la version 18.
- Vulnérabilités non corrigées accumulées sur l'image publiée.
- La collection `awx.awx` n'est plus publiée.

AWX reste utile pour **comprendre** le modèle Tower/AAP, dont il est l'amont historique. Il ne
devrait plus être choisi pour un nouveau déploiement en production.

### Red Hat Ansible Automation Platform — l'offre commerciale

**AAP 2.7, juin 2026.** Composants : Platform Gateway (authentification et interface unifiées),
Automation Controller, Automation Hub privé, EDA Controller, Automation Portal en self-service,
assistant Lightspeed.

Points structurants :

- **Installation conteneurisée ou OpenShift uniquement.** Le paquet RPM s'arrête à la 2.6.
- Licence **par nœud géré**, abonnement annuel, tarifs non publics.
- Essai gratuit de 60 jours.
- Cycle de support de 18 mois.

### ⭐ Semaphore UI — le choix de la formation

**2.19.12, août 2026, licence MIT.** Interface écrite en Go, installable par paquet, sans
Kubernetes, opérationnelle en une quinzaine de minutes.

| Fonction | Community (gratuit) | Pro (~490 $/an) | Enterprise |
|---|---|---|---|
| Templates, inventaires, Key Store chiffré | Oui | | |
| Planification cron | Oui | | |
| Webhooks entrants (Integrations) | Oui | | |
| Notifications (Slack, Teams, Telegram, courriel) | Oui | | |
| Droits par projet | Oui | | |
| API REST, serveur MCP | Oui | | |
| Terraform, OpenTofu, PowerShell, Bash | Oui | | |
| **Workflows** (enchaînement de templates) | | Oui | |
| **Exécuteur Docker**, runners de projet | | Oui | |
| **LDAP / Active Directory**, **OIDC**, TOTP | | Oui | |
| Exécuteur Kubernetes, haute disponibilité | | | Oui |

L'édition Community couvre largement le besoin d'une petite ou moyenne équipe.

### Les autres options vivantes

| Solution | Statut 2026 | Remarque |
|---|---|---|
| **Rundeck** 6.2 | Actif, Apache 2.0 | Orienté exécution d'opérations, plugin Ansible 5.1 |
| **Foreman** + `foreman_ansible` | Actif | Pertinent si Foreman gère déjà le provisionnement |
| **Uyuni** / SUSE Multi-Linux Manager | Actif | Ansible intégré à une gestion de parc complète |
| **Jenkins** + plugin Ansible | Actif | Raisonnable si Jenkins est déjà en place |
| **Kestra**, **Windmill** | Actifs | Ordonnanceurs généralistes, Ansible parmi d'autres |
| **Ansible Forms** | Actif | Formulaires devant des playbooks — plusieurs CVE en 2026 |
| **Polemarch** | Dormant | Dernière publication janvier 2025 |

### Grille de choix

| Situation | Solution |
|---|---|
| Équipe restreinte, pas de Kubernetes | **Semaphore Community** |
| Besoin de LDAP/SSO, budget limité | Semaphore Pro |
| Grand compte, support contractuel, audit | **AAP** |
| Jenkins ou Foreman déjà en place | Le plugin correspondant |
| Découverte du modèle Tower | AWX, en laboratoire uniquement |

## 3. Le modèle de données de Semaphore

| Objet | Rôle |
|---|---|
| **Project** | Cloison principale. Droits et objets y sont rattachés. |
| **Key Store** | Identifiants chiffrés : clés SSH, mots de passe, mot de passe vault |
| **Repository** | Dépôt Git contenant les playbooks |
| **Inventory** | Fichier du dépôt, contenu saisi, ou inventaire dynamique |
| **Environment** | Variables et variables d'environnement injectées |
| **Task Template** | Association dépôt + playbook + inventaire + identifiants |
| **Schedule** | Déclenchement cron d'un template |
| **Integration** | Point d'entrée webhook déclenchant un template |

Le dépôt Git reste la **source de vérité**. Semaphore ne stocke aucun playbook : il clone le
dépôt à chaque exécution. Tout ce qui a été construit du module 01 au module 11 continue de
s'appliquer.

### Ce qu'il faut savoir avant de déployer

- Semaphore appelle **`ansible-playbook` localement** : Ansible doit être installé sur la même
  machine. L'édition Community n'a pas d'*execution environment*.
- Il installe **automatiquement** les dépendances : à chaque exécution, il cherche
  `collections/requirements.yml` et `requirements.yml` dans le dépôt cloné et lance
  `ansible-galaxy install`. Le module 06 prend ici tout son sens.
- Le paquet `.deb` ne fournit **que le binaire**. Ni utilisateur système, ni unité systemd, ni
  répertoire de configuration : c'est au déploiement de les créer.

## 4. Déployer Semaphore par Ansible

Installer l'interface d'automatisation à la main serait contradictoire. Le TP le fait avec un
rôle.

```
Prérequis (git, ansible-core) → compte de service → répertoires
  → téléchargement du .deb → installation
  → génération des clés (une seule fois) → config.json
  → migrations → unité systemd → démarrage
  → compte administrateur (si absent)
```

Deux difficultés méritent l'attention.

**Les clés de chiffrement.** `config.json` contient trois secrets de 32 octets encodés en
base64. Les régénérer à chaque exécution rendrait le rôle non idempotent et, surtout,
**rendrait illisible tout le Key Store**. Le rôle lit donc la configuration existante si elle
est présente, et ne génère les clés qu'au premier déploiement.

```yaml
- name: Verifier si une configuration existe deja
  ansible.builtin.stat:
    path: /etc/semaphore/config.json
  register: semaphore_config_existante

- name: Reutiliser les cles existantes
  ansible.builtin.set_fact:
    semaphore_cookie_hash: "{{ semaphore_config_lue.cookie_hash }}"
  vars:
    semaphore_config_lue: "{{ semaphore_config_brute.content | b64decode | from_json }}"
  when: semaphore_config_existante.stat.exists
  no_log: true
```

**La création de l'administrateur.** `semaphore user add` **échoue** si le compte existe déjà.
On interroge donc `semaphore user list` avant de décider.

> **Attention**
> Les variables `SEMAPHORE_ADMIN`, `SEMAPHORE_ADMIN_PASSWORD` et consorts ne sont lues que par
> le script d'entrée de l'image Docker. Sur une installation par paquet, elles n'ont **aucun
> effet** — c'est l'erreur la plus fréquente.

## 5. Déclenchement par Git

Semaphore expose un point d'entrée par intégration :

```
POST /api/integrations/<alias>
```

Méthodes d'authentification : aucune, `github` (signature `X-Hub-Signature-256` en HMAC-SHA256),
`bitbucket`, `hmac` avec en-tête personnalisé, `token`, `basic`.

> GitLab n'a pas de méthode dédiée : il envoie un jeton en clair et non une signature. Utilisez
> `token` avec l'en-tête `X-Gitlab-Token`.

La chaîne complète devient : poussée sur Git → webhook → Semaphore → clone du dépôt →
installation des dépendances → exécution du playbook → notification. C'est le module 10 conduit
depuis une interface.

---

## TP 11 — Déployer et exploiter Semaphore UI

**Durée : 35 min.** Corrigé : [`corrige/tp11-semaphore/`](../corrige/tp11-semaphore/)

### Objectif

Installer Semaphore sur `tools` avec un rôle, puis exécuter le fil rouge depuis l'interface.

### Énoncé — partie Ansible

Écrire un rôle `semaphore` installant l'édition **Community** :

1. Prérequis : `git`, `ansible-core`, `openssl`.
2. Compte de service système, sans shell, et les répertoires `/etc/semaphore` (0750) et
   `/var/lib/semaphore` (0750, plus `secrets` en 0700).
3. Téléchargement et installation de `semaphore_community_2.19.12_linux_amd64.deb`.
4. **Génération des trois clés de chiffrement au premier déploiement seulement**, réutilisation
   de celles de `config.json` ensuite.
5. `config.json` en SQLite — attention, le chemin de la base est la clé `sqlite.host`.
6. `semaphore migrate`.
7. Unité systemd, puisque le paquet n'en fournit pas.
8. Compte administrateur, **uniquement s'il n'existe pas déjà**.
9. Attente que l'interface réponde.

```bash
ansible-playbook semaphore.yml
ansible-playbook semaphore.yml     # idempotence : changed=0
```

### Énoncé — partie interface

Depuis `http://192.168.56.31:3000` :

> **Le contrôleur change.** Votre poste installe Semaphore sur `tools`, puis `tools` exécute
> les playbooks du dépôt. Une modification locale ne sera donc visible dans l'interface
> qu'après sa publication dans Git. La clé privée du Key Store doit correspondre à une
> clé publique autorisée pour le compte `ansible` sur les cibles (TP 03). L'accès au dépôt
> Git et l'accès SSH aux VMs sont deux accès distincts, même si le Key Store gère les deux.

1. **Projet** « Formation Ansible ».
2. **Key Store** : la clé SSH d'accès aux machines, et le mot de passe vault du module 11.
3. **Repository** : le dépôt Git du fil rouge, branche `main`.
4. **Inventory** : un inventaire **dédié à Semaphore**, associé à la clé SSH du Key Store.

   > **Attention**
   > L'inventaire du TP 02 **ne fonctionne pas ici**. Il référence
   > `.vagrant/machines/<nom>/virtualbox/private_key`, une clé propre au poste du stagiaire et
   > absente du dépôt cloné par Semaphore. Il impose de plus `ansible_user: vagrant`, alors que
   > le compte de service `ansible` a été créé au TP 03. Or une variable d'inventaire
   > **prime sur** une clé fournie par l'interface : il faut donc un inventaire sans chemin de
   > clé et utilisant le bon compte.
5. **Task Template** exécutant `site.yml`.
6. **Exécution**, puis lecture du journal.
7. **Schedule** : exécution quotidienne du playbook de patching.
8. **Integration** : webhook déclenché par une poussée sur le dépôt Git.
9. Créer un second utilisateur en lecture seule et vérifier ce qu'il peut faire.

> **Relier les objets.** Créez un second Task Template pour `playbooks/patching.yml`, puis
> associez-lui le Schedule : planifier le template `site.yml` ne lance pas le patching.
> Le webhook exige que le serveur Git puisse joindre Semaphore ; un Git hébergé sur Internet
> ne peut pas appeler directement `192.168.56.31`. Dans le lab, utilisez le Git local prévu
> par le formateur ; à défaut, retenez l'exécution manuelle pour cette partie.

### Points d'attention

- Les clés de chiffrement ne se régénèrent **jamais** : le Key Store deviendrait illisible.
- `semaphore user add` n'est pas idempotent.
- Le paquet sans suffixe `community` est le binaire Pro ; les deux portent le même nom de
  paquet et s'écrasent.
- Semaphore installe lui-même les collections déclarées dans le dépôt.
- Le mot de passe administrateur est passé en clair dans le TP : en production il vient du vault.

### ⚠️ Pièges courants

| Symptôme | Cause |
|---|---|
| Aucun compte administrateur créé | Variables `SEMAPHORE_ADMIN_*` utilisées hors Docker |
| Identifiants du Key Store illisibles | Clés de chiffrement régénérées |
| `BoltDB not supported` | Dialecte supprimé en 2.19 |
| Le service ne démarre pas | Le `.deb` ne fournit pas d'unité systemd |
| Module introuvable à l'exécution | Collection absente de `collections/requirements.yml` |
| `Permission denied (publickey)` depuis Semaphore | Inventaire renvoyant vers les clés Vagrant du poste |
| Webhook GitLab rejeté | `auth_method: github` au lieu de `token` |

### 🚀 Pour aller plus loin

- Comparer avec AWX : démonstration formateur sur k3s, et constat du gel du projet.
- Ajouter une notification Slack ou Telegram sur échec.
- Consulter l'API REST : `curl -H "Authorization: Bearer <jeton>" http://…/api/projects`.

---

## 🔑 Points clés

- Une interface web n'ajoute **aucune capacité** à Ansible : elle ajoute traçabilité, droits,
  planification et self-service.
- **AWX est gelé depuis juillet 2024** : à ne plus déployer en production.
- **AAP 2.7** est conteneurisé uniquement, licence par nœud géré.
- **Semaphore Community** couvre Key Store, planification, webhooks et droits par projet.
  Workflows, Docker et LDAP/OIDC sont payants.
- Le **dépôt Git reste la source de vérité** : l'interface ne stocke pas les playbooks.
- Semaphore **installe lui-même** les collections déclarées dans le dépôt.
- Les clés de chiffrement se génèrent **une fois pour toutes**.

---

**Module précédent :** [11 — Gestion des secrets](11-Secrets.md)
**Module suivant :** [13 — Provisioning : Proxmox et VMware](../J3-Perimetres-Avances/13-Provisioning.md)
