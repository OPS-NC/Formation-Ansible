# Rapport de validation du lab

Validation en conditions réelles du 22 septembre 2026, sur le poste Ubuntu 26.04 de référence.
**Les 14 TP ont été exécutés**, sur de vraies machines virtuelles, jusqu'au test d'idempotence.

Ce fichier remplace l'audit statique précédent, dont tous les points ouverts sont tranchés
plus bas (§5).

---

## 1. Environnement réel

### Poste de travail

| Élément | Version |
|---|---|
| Système | Ubuntu 26.04.1 LTS (`resolute`), noyau 7.0.0-31-generic |
| Matériel | 12 cœurs, 61 Go de RAM, 166 Go libres |
| `ansible-core` | **2.21.4**, paquet communautaire `ansible` 14.4.0, Python 3.14.4 |
| `ansible-lint` | 26.8.0 |
| `molecule` | 26.8.0 |
| `ansible-builder` | 3.1.1 |
| `pre-commit` | 4.6.2 |
| VirtualBox | **7.2.6** (`multiverse` Ubuntu, `virtualbox-dkms` 7.2.6-dfsg-4) |
| Vagrant | 2.4.9 |
| podman | 5.7.0 (crun, overlay, rootless) |
| kubectl | v1.36.4 (snap Canonical) |
| helm | v4.3.0 |

Les versions d'Ansible, d'`ansible-lint` et de Molecule correspondent **exactement** à ce
qu'annonce le module 02. L'installation par `pipx` s'est déroulée sans incident.

### Boxes

| Box | Version épinglée | Système réel observé |
|---|---|---|
| `bento/debian-13` | 202510.26.0 | Debian 13.1 → **13.7** après TP 06, Python 3.13.5 |
| `bento/rockylinux-10` | 202512.01.0 | Rocky 10.1 → **10.2** après TP 06, Python 3.12.11 |
| `vyos/current` | 20240817.00.20 | VyOS 1.5-rolling-202408170020 |

Les trois boxes sont **disponibles au téléchargement** et s'importent sans erreur.

### Note sur la RAM

Le poste disposant de 61 Go, les VM des jours précédents n'ont **pas** été arrêtées, sauf
`net01` avant le TP 14. Les huit machines du lab tiennent largement. La consigne d'arrêt reste
valable pour le poste de 16 Go décrit dans le README.

---

## 2. Déroulé par TP

Durées mesurées, hors téléchargement des boxes. `vagrant up` initial (4 VM) : **4 min 47 s**,
dont environ 1 min de téléchargement de la box Rocky.

| TP | Sujet | Exécuté | Résultat | Durée |
|---|---|---|---|---|
| 01 | Mise en place du lab | oui | 4 VM `running`, `ping` → `pong` sur les 4 | ~5 min |
| 02 | Inventaire du fil rouge | oui | précédence et 5 motifs de ciblage conformes | < 1 min |
| 03 | Premier playbook multi-OS | oui | `changed=0` au 2ᵉ passage sur 4/4 | 10 s + 7 s |
| 04 | Serveurs web nginx | oui | `changed=0` au 2ᵉ passage sur 2/2 | 16 s + 8 s |
| 05 | Du playbook aux rôles | oui | `changed=0` au 2ᵉ passage sur 4/4 | 23 s + 17 s |
| 06 | Patching orchestré | oui | 3 serveurs, redémarrages réels, rapport produit | 4 min 32 s |
| 07 | Inventaire construit | oui | groupes conformes, avec et sans cache de facts | < 1 min |
| 08 | Molecule et qualité | oui | `molecule test` complet, 0 échec | 1 min 40 s |
| 09 | Chaîne d'intégration | partiel | EE construit, `pre-commit` vert ; CI non testée | 2 min 36 s |
| 10 | Secrets chiffrés | oui | lecture `dev` et `prod`, sortie conforme | < 1 min |
| 11 | Semaphore UI | oui | service actif, UI en 200, `changed=0` au 2ᵉ passage | 18 s |
| 12 | Provisioning | partiel | pas d'hyperviseur ; greffons chargés et configurés | < 1 min |
| 13 | Automatisation VyOS | oui | routeur réel, 3 playbooks au vert | 48 s + 1 min |
| 14 | Cluster k3s | oui | 3 nœuds `Ready`, application déployée, idempotent | 1 min 09 s |

### Contrôles transverses

| Contrôle | Résultat |
|---|---|
| `ansible-lint --profile production corrige/` | 90 fichiers, **0 violation** |
| `--syntax-check` des 15 playbooks | tous valides |
| `pre-commit run --all-files` | 6 hooks au vert |
| Liens internes des 35 fichiers Markdown | aucun cassé |
| Idempotence (`changed=0` au 2ᵉ passage) | TP 03, 04, 05, 08, 11, 13, 14 |

---

## 3. Bugs rencontrés et corrigés

**27 commits**, un par correction. Tous vérifiés avant commit : `ansible-lint` au profil
production, `--syntax-check`, puis exécution réelle.

### Bloquants — le TP ne pouvait pas aboutir

| # | Symptôme | Cause | Correction | Commit |
|---|---|---|---|---|
| 1 | `--check --diff` → `failed=1` sur 4/4 VM | `authorized_key` ne peut pas déduire le chemin quand le compte n'existe pas encore | option `path` explicite | `41fd97f` |
| 2 | idem dans le rôle `base` du TP 05 | le rôle reprend le playbook du TP 03 | même correction | `f7fdccc` |
| 3 | `404 Not Found` sur les `.deb` nginx | box épinglée, cache apt périmé, paquets retirés du miroir | `update_cache` + `cache_valid_time` | `f54268d` |
| 4 | idem rôle `nginx` (conteneur neuf) | même cause, non couverte par le rôle | idem | `db9515c` |
| 5 | idem rôle `semaphore` sur `tools` | `tools` n'est pas dans `serveurs`, jamais patchée | idem | `2fe11ba` |
| 6 | `dpkg: error processing package grub-pc` | `grub-pc` redemande son disque ; la box n'a **aucune** réponse debconf | pré-amorçage debconf avant la mise à jour | `4d315ce` |
| 7 | contrôle de santé TP 06 : `Errno 111 Connection refused` après 12 essais | `uri` suit le 301 du vhost `ancien` (TP 04) vers le port 443, où rien n'écoute | `follow_redirects: none` | `4fa2ef0` |
| 8 | `molecule test` : `The role 'nginx' was not found` | Molecule génère son propre `ansible.cfg` dans un répertoire éphémère ; les chemins relatifs du projet n'y résolvent rien | `roles_path` dans `molecule.yml` | `6211c41` |
| 9 | `ansible-builder` : `403 Forbidden` sur l'image de base | organisation `ansible` au lieu d'`ansible-community` | image corrigée | `0b79a2e` |
| 10 | `pre-commit run --all-files` échoue | `yamllint --strict` refuse les fichiers vault et le `on:` des workflows | `.yamllint` corrigé | `d7628f6` |
| 11 | `Failed to import the required Python library (packaging)` | `ansible.builtin.pip` importe `packaging` avec l'interpréteur de la cible | paquet `python3-packaging` | `f2758bb` |
| 12 | greffon vSphere jamais chargé | `vmware.vmware.vms` n'accepte que les noms en `vms.yml`/`vmware_vms.yml` | fichier renommé | `beb12b8` |
| 13 | `vagrant up net01` : IP hors plage, invité non détecté, interfaces nues, clé SSH perdue | quatre défauts enchaînés (voir §3.1) | Vagrantfile + `bootstrap-vyos.sh` | `fcd8906` |
| 14 | VyOS : `Access denied` | l'inventaire déclarait un compte `vagrant` **inexistant** sur la box | compte `vyos` + clé RSA Vagrant | `a24042b` |
| 15 | VyOS : `The authenticity of host ... can't be established` | libssh ignore `accept-new` ; `host_key_auto_add` appartenait à paramiko, retiré en 2.21 | `ssh-keyscan` documenté en préparation | `6e65846` |
| 16 | `Failed to import the required Python library (kubernetes)` | le play `localhost` utilise le Python **système**, pas celui du venv pipx | `ansible_python_interpreter: "{{ ansible_playbook_python }}"` | `8b9d0d6` |
| 17 | `AnsibleUndefinedVariable: 'ansible_managed' is undefined` | `kubernetes.core.k8s` rend le gabarit lui-même, sans les variables de `template` | mention écrite en clair | `aeb9c92` |

### 3.1 Le cas VyOS

Le TP 13 était le plus atteint : six corrections ont été nécessaires pour qu'il démarre.

1. **Adresse hors plage.** Le Vagrantfile donnait `10.10.20.1` à la seconde carte, hors de
   `192.168.56.0/21` — la seule plage host-only autorisée par défaut, que le module 02
   documente pourtant lui-même. Le support se contredisait.
2. **Invité non détecté.** `vagrant up` échouait *après* le démarrage. La cause n'est pas le
   dossier partagé, pourtant désactivé : l'action `synced_folders` de Vagrant 2.4.9 interroge
   l'invité sans rattraper l'échec de détection. `vm.guest = :debian` le court-circuite.
3. **Interfaces nues.** Vagrant ne sait pas adresser une interface sur VyOS.
4. **Clé SSH perdue.** VyOS régénère ses `authorized_keys` au démarrage : la clé insérée par
   Vagrant ne survit pas, et `vagrant reload` casse l'accès.
5. **Compte et type de clé.** Le compte est `vyos`, pas `vagrant`, et seule la clé **RSA** est
   acceptée.
6. **Provisionnement non privilégié.** Le plus coûteux à trouver : un `configure`/`commit`
   lancé **par root** laisse le système de configuration VyOS dans un état où toute commande
   ultérieure de l'utilisateur `vyos` échoue sur un laconique `Set failed` — y compris celles
   des modules `vyos.vyos`. Établi par comparaison avec une box vierge (`--no-provision`).

### Non bloquants — cohérence du support

| # | Écart | Correction | Commit |
|---|---|---|---|
| 18 | « Résultat attendu » en JSON alors que l'`ansible.cfg` du dépôt force le YAML | sorties réelles | `975151c` |
| 19 | VirtualBox `multiverse` déclaré incompatible avec le noyau 7.0 | c'est faux, voir §5 | `07f9bbc` |
| 20 | README des corrigés : `--check` **avant** la première application | ordre aligné sur le module 04, voir §3.2 | `5d8b92a` |
| 21 | horodatage dans `index.html.j2` : `changed=1` à chaque passage | horodatage retiré (TP 04 et TP 05) | `82cf926` |
| 22 | avertissement de dépréciation `ansible_date_time` à chaque exécution | `ansible_facts['date_time']` | `b4fed3c` |
| 23 | détection de redémarrage Debian inopérante | voir §5 | `fddc7fd` |
| 24 | site nginx par défaut sur Rocky : assertion Molecule sans objet | voir §5 | `c8da988` |
| 25 | TP 10 : « code retour 4 » et message obsolète | 1 pour `ansible-vault`, 4 pour `ansible-playbook` | `6513b10` |
| 26 | TP 12 : dépendances Python non documentées | `pipx inject` ajouté | `beb12b8` |
| 27 | `kubernetes-client` n'existe pas dans Ubuntu 26.04 | `snap install kubectl --classic` | `4a19741` |

### 3.2 L'ordre `--check` / application

Le point de cohérence le plus important pour la salle. Le module 04 enseigne explicitement
l'ordre **appliquer → vérifier l'idempotence → simuler en audit de dérive**, et explique
pourquoi. Les README des corrigés 03, 04 et 05 prescrivaient l'**inverse**.

Sur machine vierge, cet ordre échoue mécaniquement : le paquet n'est que simulé, donc le
service et le compte qu'il fournit n'existent pas quand les tâches suivantes les interrogent.
Mesuré : TP 03 → `failed=1` sur 4/4 VM, TP 04 → `failed=1` sur 2/2.

L'élève était donc envoyé dans l'échec que son support venait de lui dire d'éviter. Les README
suivent désormais le module 04, avec un renvoi vers son explication.

---

## 4. Ce qui n'a pas pu être testé

| Sujet | TP | Raison |
|---|---|---|
| Provisioning Proxmox et vSphere réel | 12 | aucune infrastructure disponible |
| Molecule dans un exécuteur de CI | 09 | aucun exécuteur GitLab ni GitHub self-hosted |
| `ansible-navigator run --eei` | 09 | l'image est construite, son exécution n'a pas été jouée |
| Usage de l'interface Semaphore | 11 | création de projet, clés, tâches, webhook : manipulation en salle |
| NetBox comme source de vérité | 13 | aucune instance NetBox |
| États `rendered` / `parsed` hors ligne | 13 | limite déjà documentée dans le corrigé, non ré-éprouvée |
| Modules `ansible.windows` | 16 | aucune cible Windows ; module sans TP |
| `ansible-rulebook` / EDA | 16 | module sans TP |

Pour le TP 12, la validation est allée **au-delà du `--syntax-check`** annoncé : l'assertion
d'entrée échoue bien sur secret manquant, et les deux greffons d'inventaire sont chargés et
configurés jusqu'à la tentative de connexion réseau — le dernier point atteignable sans
hyperviseur.

---

## 5. Statut des points ouverts de l'ancien audit

### Point 1 — Validation de bout en bout du lab

**Traité.** Les huit VM démarrent, le fil rouge s'applique et le second passage donne
`changed=0`. Les modules VirtualBox se compilent sur le noyau 7.0 (voir ci-dessous).

La réserve « premier passage réel avant toute simulation » était fondée : c'est le point §3.2.

### Point 2 — Faits à confirmer sur les images

| À vérifier | Statut | Constat |
|---|---|---|
| `dnf needs-restarting -r` et ses codes retour sur Rocky 10 | **confirmé** | La commande existe et fonctionne. `rc=0` si aucun redémarrage, `rc=1` sinon — les deux cas observés. `dnf-plugins-core` est **déjà présent** dans la box. Nuance relevée : le sous-commande vient de `python3-dnf-plugins-core` ; le binaire autonome `/usr/bin/needs-restarting` est fourni par `yum-utils`. |
| Producteur de `/var/run/reboot-required` sur `bento/debian-13` | **confirmé — il n'y en a pas** | `update-notifier-common` n'existe pas dans Debian 13 (`Candidate: (none)`) ; aucun crochet apt ne mentionne `reboot-required` ; le fichier n'apparaît jamais. C'est un mécanisme **Ubuntu**. La branche Debian du TP 06 ne se déclenchait donc **jamais**. Remplacée par la comparaison du noyau courant au plus récent noyau installé (`linux-version`, paquet `linux-base`). |
| Emplacement du serveur nginx par défaut sur Rocky | **confirmé — l'assertion ne prouvait rien** | `/etc/nginx/conf.d/` est **vide** : aucun `default.conf`. Le serveur par défaut est déclaré dans `/etc/nginx/nginx.conf`. L'assertion Molecule passait trivialement. Elle vérifie désormais le **comportement**. Le résultat final était néanmoins correct, pour une raison que le support n'exposait pas : `nginx.conf` inclut `conf.d/*.conf` **avant** de déclarer son serveur, et le premier serveur d'un port en devient le défaut. |
| Seconde carte réseau sur `vyos/current` | **confirmé — elle existe** | `eth0` (NAT), `eth1` et `eth2` sont bien présentes. Mais son adresse était hors de la plage host-only autorisée, ce qui empêchait le démarrage. |
| Disponibilité de la box `vyos/current` | **infirmé** | La box se télécharge et s'importe sans difficulté. Elle est en VyOS **1.5**-rolling, et non 1.4 : la remarque « à reconstruire pour travailler sur VyOS 1.5 » est caduque. |

### Point 3 — Exécutions non tentées

| Sujet | TP | Statut |
|---|---|---|
| `molecule test` complet avec Podman | 08 | **fait** — 7 actions, 0 échec, idempotence comprise, sur Debian 13 et Rocky 10 |
| Construction de l'execution environment | 09 | **fait** — 2 min 36 s, 12 collections présentes |
| Molecule dans un exécuteur de CI | 09 | **toujours non vérifié** |
| Installation de Semaphore | 11 | **fait** — service actif, UI en 200, idempotent |
| Provisioning Proxmox et vSphere | 12 | **toujours non vérifié** (greffons chargés, connexion non établie) |
| Playbooks VyOS 01 et 02 | 13 | **faits** — contre un routeur réel |
| Cluster k3s et déploiement applicatif | 14 | **fait** — 3 nœuds, adresses internes distinctes, Helm compris |

### Point 4 — Choix assumés

| Affirmation | Statut |
|---|---|
| `postgres_port` ne configure que le pare-feu | inchangé, documenté |
| Le fichier `MAINTENANCE` est un témoin | inchangé, documenté |
| Les blocs `location` de proxy renvoient 502 | inchangé, annoncé |
| La box `vyos/current` est figée depuis août 2024 | exact, et **suffisante** : elle est en VyOS 1.5 |
| Le registre de boxes Vagrant ferme le 31/12/2026 | inchangé — **échéance à traiter** (§6) |

### Affirmation de l'ancien audit qui s'est révélée fausse

L'`ansible.cfg` affirmait que son `roles_path` rendait les rôles « resolvables […] y compris
depuis les scénarios Molecule qui les appellent ». C'est **faux** : Molecule s'exécute depuis
un répertoire éphémère où ces chemins relatifs ne désignent rien. Le lint statique ne pouvait
pas le révéler.

De même, le module 02 affirmait que le paquet VirtualBox de `multiverse` ne compile pas sur le
noyau 7.0. **Infirmé** : Ubuntu rétroporte le correctif, `virtualbox-dkms` 7.2.6-dfsg-4 se
construit et se charge sur 7.0.0-31, et c'est avec lui que ce lab complet a tourné.

---

## 6. Recommandations avant de donner la formation

### À faire avant la session

1. **Miroiter les trois boxes** (`bento/debian-13`, `bento/rockylinux-10`, `vyos/current`) et
   les servir en interne avec `box_url` + `box_download_checksum`. Le registre HCP Vagrant
   ferme le **31 décembre 2026** : sans cela, le lab devient indémarrable. C'est le seul
   risque qui rend la formation impossible à donner.
2. **Prévoir un miroir apt local**, ou accepter que la première tâche de chaque playbook
   rafraîchisse le cache. La combinaison box épinglée + point release Debian fait disparaître
   des `.deb` du miroir : c'est la cause de **trois** des bugs bloquants rencontrés.
3. **Dérouler le lab une fois de bout en bout, sur le poste de la salle**, une semaine avant.
   Compter environ 25 minutes d'exécution machine pour les 14 TP, hors téléchargements.
4. **Télécharger les images de conteneurs à l'avance** :
   `geerlingguy/docker-debian13-ansible`, `geerlingguy/docker-rockylinux10-ansible`,
   `ghcr.io/ansible-community/community-ee-base`, `nginx:1.29-alpine`, le chart `podinfo`.
5. **Vérifier le compte utilisé.** La validation a eu lieu sous un compte quelconque ; aucun
   nom d'utilisateur ni chemin `$HOME` n'est codé en dur dans le dépôt — tout passe par
   `lookup('ansible.builtin.env', 'HOME')`. Un compte `formation` fonctionnera sans
   modification.

### Points de vigilance en salle

6. **Le TP 06 redémarre réellement des machines.** Prévoir la durée : environ 4 min 30 s pour
   les trois serveurs, dont un `dnf upgrade` de 380 paquets sur Rocky. Annoncer l'attente.
7. **Le TP 13 exige `ssh-keyscan` après chaque `vagrant destroy net01`.** C'est la première
   chose à vérifier si un stagiaire est bloqué sur le routeur.
8. **`vagrant up net01` est le point le plus fragile du parcours.** Six défauts y ont été
   corrigés ; le tester avant la session, pas devant la salle.
9. **La formation demande un accès Internet correct** : boxes, collections Galaxy, images de
   conteneurs, chart Helm, script `get.k3s.io`. Pas de scénario hors ligne.

### Améliorations possibles du support

10. **Les VM du jour 3 ne sont pas dans `vagrant up`.** C'est documenté, mais un stagiaire qui
    survole le README arrivera au TP 14 sans cluster. Le rappeler à l'oral en fin de J2.
11. **`cowsay`, s'il est installé sur le poste, encadre chaque récapitulatif de banderoles
    ASCII.** Aucune sortie du support ne les montre. Désinstaller `cowsay` sur les postes de
    la salle, ou poser `ANSIBLE_NOCOWS=1`, évite une divergence visuelle déroutante dès le
    TP 03.
12. **Le volume horaire annoncé** (21 h, 7 h/jour) correspond à 6 h 45 de contenu réel par
    jour plus les pauses. Le découpage de `PLAN.md` est cohérent ; l'écart est celui, habituel,
    entre durée commerciale et temps de face-à-face.

---

## 7. Réserve sur l'historique Git

Le commit `f2758bb`, dont le message ne décrit que l'ajout de `python3-packaging` (TP 11),
emporte aussi les rafraîchissements de cache préventifs des TP 03 et 05. L'erreur est de
méthode, pas de contenu : les trois modifications sont correctes et vérifiées. L'historique
étant déjà poussé, il n'a pas été réécrit.

---

## 8. Méthode

Chaque bug a été **reproduit** avant correction, et la correction **vérifiée par exécution
réelle**, pas seulement par lint. Les affirmations infirmées — paquet VirtualBox,
`/var/run/reboot-required`, `roles_path` sous Molecule, disponibilité de la box VyOS — l'ont
été par mesure directe sur la machine, avec la sortie à l'appui, et non par raisonnement.

Quand une correction de ma part a introduit un défaut (provisionnement VyOS lancé en root,
heredoc Ruby non interpolé), le diagnostic a été mené jusqu'à la cause et consigné comme les
autres.
