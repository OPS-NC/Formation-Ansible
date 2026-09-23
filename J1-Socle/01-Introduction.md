# Module 01 — Introduction et positionnement

> **Jour 1** · 45 min · Théorie
> Prérequis : aucun. Module d'ouverture.

## Objectifs

À la fin de ce module, vous savez :

- expliquer le modèle d'exécution d'Ansible (agentless, push, SSH) et ce qu'il implique ;
- définir idempotence, inventaire, play, tâche, module, plugin, collection ;
- distinguer `ansible-core`, le paquet communautaire `ansible` et Red Hat Ansible Automation Platform ;
- situer la version que vous utilisez dans le cycle de vie du projet ;
- dire quand Ansible n'est pas le bon outil.

---

## 1. Le problème

Un parc de serveurs dérive. Trois causes, toujours les mêmes :

1. **L'intervention manuelle.** Une modification appliquée en SSH sur un serveur et oubliée sur les deux autres.
2. **Le script non rejouable.** Un script shell d'installation qui échoue s'il est lancé deux fois, ou qui suppose un état initial précis.
3. **La documentation périmée.** Le `README` décrit l'installation de l'an dernier.

La gestion de configuration répond à ces trois points en déplaçant la description du système depuis la documentation vers du code exécutable et rejouable.

## 2. Le modèle Ansible

Quatre décisions de conception structurent l'outil.

### 2.1 Sans agent (*agentless*)

Aucun démon n'est installé sur les machines gérées. Ansible se connecte en SSH (Linux, BSD, réseau) ou en WinRM/PSRP/SSH (Windows), y dépose du code, l'exécute, récupère le résultat en JSON, puis nettoie.

Conséquences directes :

- **Prérequis minimaux** sur la cible : un accès SSH et un interpréteur Python (sauf modules `raw` et équipements réseau).
- **Pas de port propre à Ansible** : le port SSH doit déjà être accessible depuis le contrôleur ; aucun agent Ansible n'est à mettre à jour.
- **Le nœud de contrôle devient un actif critique** : il détient les accès à tout le parc. Il doit être traité comme un bastion.
- **Performance liée au nombre de connexions SSH** : c'est le facteur limitant sur les grands parcs (voir module 07).

### 2.2 Mode *push*

C'est l'opérateur (ou la CI, ou l'ordonnanceur) qui déclenche l'exécution. Ansible ne surveille pas en continu l'état des machines, contrairement à Puppet ou Chef qui fonctionnent par *pull* périodique.

Conséquence : **Ansible ne corrige pas la dérive tant qu'on ne le relance pas.** Deux réponses possibles :

- exécution planifiée (cron, ordonnanceur, WebUI — module 12) ;
- exécution déclenchée par événement (Event-Driven Ansible — module 16).

### 2.3 Idempotence

Une exécution idempotente produit le même état final quel que soit le nombre de fois où elle est lancée. C'est la propriété centrale de l'outil.

```
1er run  → "package nginx installé"        → changed
2e  run  → "package nginx déjà installé"   → ok
```

Ansible rapporte quatre états par tâche : `ok`, `changed`, `skipped`, `failed`. Un second passage qui ne produit aucun `changed` est le test d'idempotence — il est vérifié systématiquement à partir du module 04, et automatisé par Molecule au module 09.

L'idempotence n'est **pas automatique** : elle est portée par les modules. `ansible.builtin.package` sait vérifier l'état d'un paquet ; avec `ansible.builtin.command`, vous devez encadrer la commande et déclarer quand elle modifie réellement le système.

> `creates` et `removes` peuvent empêcher une commande de se rejouer. `changed_when` règle
> seulement ce qu'Ansible **rapporte** : la commande s'exécute tout de même. Mettre
> `changed_when: false` sur une commande qui modifie le système masque donc le changement,
> sans rendre cette commande idempotente.

### 2.4 Déclaratif, mais à exécution ordonnée

Vous décrivez un état cible (« ce paquet est présent », « ce service est démarré »), pas la suite de commandes pour y parvenir. En revanche, contrairement à Terraform ou Kubernetes, **Ansible n'a pas de graphe de dépendances ni de fichier d'état** : les tâches s'exécutent dans l'ordre d'écriture, de haut en bas.

C'est une simplification importante : le comportement est lisible et prévisible, mais l'ordre relève de votre responsabilité.

## 3. Architecture et vocabulaire

```
┌──────────────────────────────┐
│      Nœud de contrôle        │   Linux ou macOS uniquement
│                              │   (pas de contrôleur Windows)
│  ansible-playbook            │
│  ansible.cfg                 │
│  inventaire  ───────┐        │
│  playbooks / rôles  │        │
│  collections        │        │
└─────────────────────┼────────┘
                      │  SSH (22) / WinRM (5985-5986) / API HTTPS
        ┌─────────────┼──────────────┬──────────────────┐
        ▼             ▼              ▼                  ▼
   ┌─────────┐   ┌─────────┐   ┌──────────┐      ┌───────────┐
   │ Debian  │   │  Rocky  │   │ Switch   │      │  API      │
   │ Python3 │   │ Python3 │   │ (pas de  │      │  Proxmox  │
   │         │   │         │   │  Python) │      │  vSphere  │
   └─────────┘   └─────────┘   └──────────┘      └───────────┘
      nœuds gérés                réseau            exécution
                              (exécution sur      sur le contrôleur
                               le contrôleur)
```

| Terme | Définition |
|---|---|
| **Nœud de contrôle** | Machine d'où Ansible est lancé. Linux ou macOS. Windows non supporté (WSL2 accepté). |
| **Nœud géré** | Machine cible. Ne connaît pas Ansible. |
| **Inventaire** | Liste des nœuds gérés, organisée en groupes, avec leurs variables. Statique ou dynamique. |
| **Module** | Unité de travail (`copy`, `package`, `service`). Code exécuté sur la cible, qui retourne du JSON. |
| **Tâche** (*task*) | Appel d'un module avec ses paramètres. |
| **Play** | Association d'un groupe de nœuds et d'une liste de tâches. |
| **Playbook** | Fichier YAML contenant un ou plusieurs plays. |
| **Rôle** | Unité de réutilisation : arborescence normalisée de tâches, variables, templates et handlers. |
| **Collection** | Format de distribution regroupant modules, rôles, plugins et playbooks sous un espace de noms. |
| **Plugin** | Code exécuté **sur le contrôleur** : connexion, inventaire, lookup, filtre, callback, stratégie. |
| **Facts** | Informations collectées automatiquement sur la cible (OS, IP, mémoire, disques). |
| **FQCN** | *Fully Qualified Collection Name* : `ansible.builtin.copy`, `community.postgresql.postgresql_db`. |

**Module ou plugin ?** Un module est transféré et exécuté sur la cible. Un plugin s'exécute sur le contrôleur. Un filtre Jinja2, un plugin d'inventaire ou un plugin de connexion ne « voient » jamais la machine distante autrement qu'à travers ce que la connexion remonte.

> Ce parcours décrit d'abord les modules d'administration Linux. Les modules réseau et ceux
> qui pilotent une API s'exécutent généralement sur le contrôleur : la cible administrée
> n'est alors pas la machine qui exécute le code Python. Cette distinction revient au jour 3.

## 4. Les trois Ansible

La confusion sur « la version d'Ansible » vient du fait que trois produits portent ce nom.

| | `ansible-core` | Paquet `ansible` | Ansible Automation Platform |
|---|---|---|---|
| **Contenu** | Moteur + collections `ansible.builtin` | `ansible-core` + ~90 collections communautaires | AAP : contrôleur, hub privé, EDA, gateway |
| **Distribution** | PyPI, dépôts distribution | PyPI (`pip install ansible`) | Abonnement Red Hat |
| **Version (sept. 2026)** | **2.21.4** | **14.4.0** | **2.7** |
| **Cadence** | 2 versions majeures/an (mai, novembre) | 1 majeure/an, mineures toutes les 4 semaines | ~1 majeure/an |
| **Usage** | Socle minimal, CI, execution environments | Poste de travail, découverte | Production d'entreprise, RBAC, support |

Ce que cela implique au quotidien :

- Installer `ansible` (le paquet communautaire) donne immédiatement `community.general`, `community.postgresql`, `cisco.ios`, etc. C'est le choix de cette formation pour le poste de travail.
- Installer `ansible-core` seul impose de déclarer explicitement chaque collection dans un `requirements.yml`. C'est le choix recommandé en CI et en production, car il rend les dépendances explicites et reproductibles (modules 06 et 10).
- **Le numéro de version du paquet ne correspond pas à celui du moteur.** Ansible 14 embarque `ansible-core` 2.21. Quand une documentation parle de « Ansible 2.9 », elle parle de l'ancienne numérotation, antérieure à la séparation de 2020.

## 5. Cycle de vie et versions (septembre 2026)

| Version `ansible-core` | Sortie | Fin de support | Statut |
|---|---|---|---|
| 2.21.x | mai 2026 | novembre 2027 | **Version cible de la formation** |
| 2.20.x | novembre 2025 | mai 2027 | Supportée |
| 2.19.x | mai 2025 | **30 novembre 2026** | Fin de vie imminente |
| 2.18.x | — | mai 2026 | Obsolète |

**Matrice Python** — c'est la contrainte la plus fréquemment rencontrée en production :

| | Versions supportées par `ansible-core` 2.21 |
|---|---|
| Nœud de contrôle | Python **3.12 à 3.14** |
| Nœud géré | Python **3.9 à 3.14** |

Conséquence concrète : une cible RHEL 8 / CentOS 7 (Python 3.6 ou 2.7) n'est plus gérable avec `ansible-core` 2.21. Il faut alors soit conserver un contrôleur avec une version ancienne, soit utiliser un *execution environment* dédié (module 10).

Les versions des distributions du lab, à titre de comparaison :

| OS | Python | Paquet du dépôt | Adapté comme contrôleur ? |
|---|---|---|---|
| Ubuntu 26.04 LTS | 3.14 | `ansible-core` 2.20.1 | Oui, mais en retard d'une version |
| Debian 13 « Trixie » | 3.13 | `ansible-core` 2.19.4 | Non — fin de vie en novembre 2026 |
| Rocky Linux 10 | 3.12 | `ansible-core` 2.16.16 | Non — version très ancienne |

C'est la raison pour laquelle le module 02 installe Ansible avec `pipx`, et non avec `apt` ou `dnf`.

## 6. Positionnement

### 6.1 Face aux autres outils de gestion de configuration

| | Ansible | Puppet | Salt | Chef |
|---|---|---|---|---|
| Agent | Non | Oui | Oui (ou SSH) | Oui |
| Mode | Push | Pull | Push et pull | Pull |
| Langage | YAML + Jinja2 | DSL Puppet | YAML + Jinja2 | Ruby |
| Courbe d'apprentissage | Faible | Moyenne | Moyenne | Élevée |
| Ordre d'exécution | Séquentiel explicite | Graphe de dépendances | Séquentiel ou graphe | Graphe |

Le choix d'Ansible se justifie par le coût d'entrée : pas d'infrastructure à déployer avant de produire un résultat, et un langage lisible par un administrateur qui n'est pas développeur.

### 6.2 Face à Terraform / OpenTofu

La règle usuelle : **Terraform provisionne, Ansible configure.**

| | Terraform / OpenTofu | Ansible |
|---|---|---|
| Objet | Cycle de vie de ressources (créer, modifier, détruire) | État interne d'un système existant |
| État | Fichier d'état (*state*) obligatoire | Aucun état persistant |
| Modèle | Graphe de dépendances, `plan` puis `apply` | Séquentiel |
| Détection de dérive | Native (`terraform plan`) | Par exécution (`--check --diff`) |

Ansible sait créer des VMs (modules 13), et c'est souvent suffisant en environnement on-premise (Proxmox, vSphere) où l'on ne veut pas gérer de *state*. En revanche, dès que l'infrastructure devient un graphe de ressources cloud interdépendantes, l'absence de *state* et de `plan` devient un handicap.

### 6.3 Quand ne pas utiliser Ansible

- **Déploiement applicatif continu sur Kubernetes** : ArgoCD ou Flux sont conçus pour cela (module 15).
- **Orchestration de conteneurs en production** : c'est le rôle de Kubernetes ou Nomad.
- **Traitement de données, boucles lourdes, logique algorithmique** : YAML + Jinja2 n'est pas un langage de programmation. Si vous écrivez des boucles imbriquées avec `selectattr` sur trois niveaux, écrivez un module Python.
- **Cible unique et action ponctuelle** : un `ssh` suffit.

## 7. Le fil rouge de la formation

Les trois journées construisent un projet unique, versionné dans Git, qui part d'un inventaire et arrive à un déploiement applicatif sur Kubernetes.

```
J1  inventaire → playbook → rôle → collection réutilisée
J2  orchestration → qualité (lint, Molecule) → CI → secrets → WebUI
J3  provisioning (Proxmox, VMware) → réseau → Kubernetes (k3s)
```

Le lab est décrit dans le module 02. Toutes les machines sont créées par un unique `Vagrantfile` : aucune installation manuelle, aucune ISO.

---

## Points clés

- Ansible est **sans agent**, en **push**, et s'exécute **dans l'ordre d'écriture**.
- L'**idempotence** est portée par les modules, pas par le moteur : `command` et `shell` doivent être encadrés.
- **Ansible 14 = `ansible-core` 2.21.** Les deux numérotations coexistent, il faut toujours préciser laquelle on cite.
- Le contrôleur exige **Python 3.12+**, les cibles **Python 3.9+**.
- Les paquets des distributions sont en retard : on installe Ansible avec **pipx** (module 02).
- Le **nœud de contrôle est un actif critique** : il détient les accès au parc entier.

## Quiz de positionnement

À traiter individuellement en 10 minutes, correction collective. L'objectif est de calibrer le rythme, pas de noter.

1. Ansible nécessite-t-il l'ouverture d'un port en entrée sur les machines gérées ? Justifiez.
2. Quelle est la différence entre les états `ok` et `changed` dans une sortie d'exécution ?
3. `ansible.builtin.shell: rm -f /tmp/cache` est-il idempotent ? Et `ansible.builtin.file: path=/tmp/cache state=absent` ?
4. Un serveur cible n'a que Python 3.6. Quelles sont vos options avec `ansible-core` 2.21 ?
5. Vous devez créer 20 VMs sur vSphere puis les configurer. Quels outils, dans quel ordre, et pourquoi ?
6. Où s'exécute un plugin de filtre Jinja2 : sur le contrôleur ou sur la cible ?

---

**Module suivant :** [02 — Nœud de contrôle et lab](02-Noeud-De-Controle.md)
