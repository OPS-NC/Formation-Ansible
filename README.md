# Formation Ansible — Administration avancée

Formation de 3 jours (21 h) à l'automatisation d'infrastructure avec Ansible : administration
de serveurs Linux, industrialisation dans Git, provisioning de VMs, automatisation réseau et
Kubernetes.

**Version cible :** `ansible-core` 2.21 / paquet communautaire Ansible 14 — état de l'art septembre 2026.

---

## Public et prérequis

**Public.** Administrateurs systèmes Linux confirmés, ingénieurs DevOps et SRE, architectes
infrastructure.

**Prérequis.**

- Ligne de commande Linux : SSH, `sudo`, `systemd`, gestion de paquets `apt` et `dnf`.
- Notions de YAML et de Git (`clone`, `commit`, `branch`).
- Aucune connaissance préalable d'Ansible n'est requise.

**Poste de travail.** Ubuntu 26.04 LTS, 16 Go de RAM, 60 Go de disque libre, virtualisation
matérielle activée (VT-x / AMD-V). Le poste est le **nœud de contrôle** des premiers TP.
Au TP 11, la VM `tools` devient aussi un nœud de contrôle pour les exécutions depuis Semaphore.

---

## Le lab

Toutes les machines virtuelles proviennent d'un unique [`Vagrantfile`](Vagrantfile).
Aucune installation manuelle, aucune ISO.

| VM | IP | Système | RAM | vCPU | Utilisation |
|---|---|---|---|---|---|
| `web01` | 192.168.56.11 | Debian 13 | 1 Go | 1 | Serveur web — J1, J2 |
| `web02` | 192.168.56.12 | Debian 13 | 1 Go | 1 | Serveur web — J1, J2 |
| `db01` | 192.168.56.21 | Rocky Linux 10 | 2 Go | 2 | Base de données, cible multi-distribution — J1, J2 |
| `tools` | 192.168.56.31 | Debian 13 | 2 Go | 2 | Semaphore UI, exécution CI — J2 |
| `k3s-master` | 192.168.56.41 | Debian 13 | 2 Go | 2 | Plan de contrôle Kubernetes — J3 |
| `k3s-node01` | 192.168.56.42 | Debian 13 | 1,5 Go | 2 | Nœud de calcul — J3 |
| `k3s-node02` | 192.168.56.43 | Debian 13 | 1,5 Go | 2 | Nœud de calcul — J3 |
| `net01` | 192.168.56.51 | VyOS | 1 Go | 1 | Routeur, automatisation réseau — J3 |

Réseau host-only `192.168.56.0/24`. Les machines du jour 3 ne démarrent pas par défaut, afin de
ménager la mémoire du poste pendant les deux premiers jours.

```bash
vagrant up                                          # lab J1 / J2  (4 VMs, ~6 Go)
vagrant up k3s-master k3s-node01 k3s-node02         # cluster J3   (3 VMs, ~5 Go)
vagrant up net01                                    # routeur J3   (1 VM,  ~1 Go)
vagrant halt                                        # arrêt
vagrant destroy -f                                  # remise à zéro
```

La procédure d'installation complète du poste est décrite dans le
[module 02](J1-Socle/02-Noeud-De-Controle.md).

---

## Parcours

### Jour 1 — Socle : de l'inventaire au rôle réutilisable

| # | Module | Durée | Contenu |
|---|---|---|---|
| 01 | [Introduction et positionnement](J1-Socle/01-Introduction.md) | 45 min | Modèle Ansible, vocabulaire, versions, positionnement |
| 02 | [Nœud de contrôle et lab](J1-Socle/02-Noeud-De-Controle.md) | 60 min | Installation pipx, `ansible.cfg`, Vagrant — **TP 01** |
| 03 | [Inventaire et commandes ad hoc](J1-Socle/03-Inventaire.md) | 60 min | Groupes, variables, précédence, patterns — **TP 02** |
| 04 | [Playbooks : fondamentaux](J1-Socle/04-Playbooks.md) | 75 min | Modules essentiels, idempotence, `--check` — **TP 03** |
| 05 | [Variables, Jinja2, handlers](J1-Socle/05-Variables-Jinja-Handlers.md) | 75 min | Templates, boucles, conditions, notifications — **TP 04** |
| 06 | [Rôles, collections, Galaxy](J1-Socle/06-Roles-Collections.md) | 75 min | Structure, réutilisation de contenu existant — **TP 05** |

### Jour 2 — Industrialisation : qualité, Git, CI/CD, exploitation

| # | Module | Durée | Contenu |
|---|---|---|---|
| 07 | [Exécution avancée](J2-Industrialisation/07-Execution-Avancee.md) | 75 min | `block`/`rescue`, `serial`, délégation, stratégies — **TP 06** |
| 08 | [Inventaires dynamiques](J2-Industrialisation/08-Inventaires-Dynamiques.md) | 45 min | Plugins, `constructed`, cache de facts — **TP 07** |
| 09 | [Qualité : lint et tests](J2-Industrialisation/09-Qualite.md) | 75 min | ansible-lint, Molecule, idempotence — **TP 08** |
| 10 | [Git et CI/CD](J2-Industrialisation/10-Git-CICD.md) | 90 min | Structure de dépôt, pipelines, execution environments — **TP 09** |
| 11 | [Gestion des secrets](J2-Industrialisation/11-Secrets.md) | 45 min | Vault, SOPS/age, coffres externes — **TP 10** |
| 12 | [Interfaces web](J2-Industrialisation/12-WebUI.md) | 60 min | Semaphore UI, AWX, AAP — **TP 11** |

### Jour 3 — Périmètres avancés : provisioning, réseau, Kubernetes

| # | Module | Durée | Contenu |
|---|---|---|---|
| 13 | [Provisioning : Proxmox et VMware](J3-Perimetres-Avances/13-Provisioning.md) | 105 min | `community.proxmox`, `vmware.vmware`, Terraform — **TP 12** |
| 14 | [Automatisation réseau](J3-Perimetres-Avances/14-Reseau.md) | 90 min | `network_cli`, resource modules, VyOS, NetBox — **TP 13** |
| 15 | [Kubernetes avec Ansible](J3-Perimetres-Avances/15-Kubernetes.md) | 105 min | Cluster k3s, `kubernetes.core`, Helm — **TP 14** |
| 16 | [Event-Driven, IA, Windows](J3-Perimetres-Avances/16-EDA-IA-Windows.md) | 45 min | `ansible-rulebook`, assistants IA, `ansible.windows` |
| 17 | [Synthèse et feuille de route](J3-Perimetres-Avances/17-Synthese.md) | 45 min | Checklist production, certification, quiz final |

---

## Organisation du dépôt

```
.
├── README.md              Ce fichier — parcours de la formation
├── PLAN.md                Plan pédagogique détaillé (découpage horaire, objectifs)
├── Vagrantfile            Définition des 8 VMs du lab
├── bootstrap.sh           Socle minimal des VMs (Python)
├── J1-Socle/              Modules 01 à 06
├── J2-Industrialisation/  Modules 07 à 12
├── J3-Perimetres-Avances/ Modules 13 à 17
└── corrige/               Projet fil rouge complet, construit TP par TP
```

Chaque module est autonome : objectifs, contenu théorique, travaux pratiques, points clés.
Les corrigés exécutables sont dans [`corrige/`](corrige/), organisés par TP.

## Fil rouge

Un projet unique est construit du premier au dernier TP :

```
TP 01-02   inventaire du parc
TP 03-05   configuration de base, serveur web, base de données, rôles
TP 06-08   orchestration du patching, qualité, tests Molecule
TP 09-11   pipeline CI, secrets chiffrés, exécution depuis une interface web
TP 12-14   provisioning, réseau, déploiement applicatif sur Kubernetes
```

## Conventions

- Les modules sont toujours appelés par leur **FQCN** (`ansible.builtin.copy`).
- Les commandes préfixées `$` s'exécutent sur le poste de travail, `#` dans une VM.
- Les blocs `> Vérification` indiquent un contrôle à effectuer avant de poursuivre.
- Les blocs `> Attention` signalent un piège connu.

## Licence

Support de formation — OPS-NC.
