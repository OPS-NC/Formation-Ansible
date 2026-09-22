# Rapport de validation du lab

Validation en conditions réelles des 22 et 23 septembre 2026, sur le poste Ubuntu 26.04 de
référence. **Les 14 TP ont été exécutés**, sur de vraies machines virtuelles, jusqu'au test
d'idempotence — puis **rejoués intégralement à froid** : lab détruit, dépôt recloné (§2.1).

Deux passes : les **corrigés** (§3), puis les **étapes d'énoncé sans playbook** (§3.3) — celles
que le formateur joue en direct, et qui avaient échappé à la première passe.

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

### 2.1 Passe à froid — la validation qui compte

Les mesures ci-dessus ont été prises au fil des corrections, sur des machines qui accumulaient
de l'état. Pour lever cette réserve, **tout a été rejoué depuis rien** le 23 septembre :
`vagrant destroy -f` sur les huit VM, puis `git clone` du dépôt dans un répertoire neuf, et les
14 TP enchaînés dans l'ordre.

**Résultat : aucun échec.** `rc=0` sur chacune des 26 étapes.

| Phase | Durée | Résultat |
|---|---|---|
| `vagrant up` (4 VM J1/J2) | 4 min | 4 machines `running` |
| TP 01 → TP 12 enchaînés | **8 min 17 s** | 26 étapes, toutes `rc=0` |
| `molecule test` (TP 08) | 1 min 33 s | 7 actions, 0 échec |
| `ansible-lint` + `pre-commit` | — | 90 fichiers, 0 violation ; 6 hooks verts |
| Construction de l'EE (TP 09) | — | image produite, 13 collections |
| `vagrant up net01` + TP 13 | 48 s + 1 min | 3 playbooks `rc=0` |
| `vagrant up` cluster k3s | 3 min 18 s | 3 machines `running` |
| TP 14 complet | 1 min 15 s | 3 nœuds `Ready`, IP internes distinctes, idempotent |

**Environ 28 minutes de temps machine** pour le parcours complet, lab détruit au départ.

Deux points valident spécifiquement les corrections les plus lourdes :

- **TP 03 et TP 04** : la 1ʳᵉ convergence passe, le 2ᵉ passage donne `changed=0`, et
  `--check --diff` en **position d'audit** donne `changed=0` lui aussi. Le réordonnancement
  des README (§3.2) est donc le bon.
- **TP 06** : sur un parc entièrement neuf, le rapport rend
  `{"db01": true, "web01": true, "web02": true}`. Les **deux** mécanismes de détection se
  déclenchent, y compris côté Debian — où il ne se déclenchait jamais avant correction.

### Deux observations relevées pendant la passe à froid

**Les VM Debian partagent leur clé d'hôte SSH.** `web01`, `web02` et `tools` présentent la même
clé ed25519 : elle est figée dans l'image `bento/debian-13`. Conséquence agréable — détruire et
recréer une VM ne déclenche **aucun** conflit de clé, contrairement à ce qu'on pourrait craindre
après un `vagrant destroy -f`. Conséquence à connaître : le `accept-new` vanté au module 02 ne
distingue pas ces trois machines, puisqu'elles ont la même identité. C'est sans gravité en lab,
mais cela mérite d'être dit si un stagiaire pose la question. VyOS, lui, régénère sa clé à
chaque création : d'où l'obligation du `ssh-keyscan` au TP 13.

**`vagrant up` peut rendre la main avant que le réseau host-only ne réponde.** Un `ping` lancé
immédiatement après a échoué, puis réussi quelques secondes plus tard. Si une commande Ansible
échoue en `UNREACHABLE` juste après un démarrage, la relancer suffit.

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

**30 commits**, un par correction. Tous vérifiés avant commit : `ansible-lint` au profil
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

## 3.3 Étapes d'énoncé sans playbook dans le corrigé

Première passe de validation : les **corrigés**. Seconde passe : les étapes d'énoncé qui
demandent une manipulation sans fichier correspondant — celles que le formateur joue en direct.
Cinq d'entre elles n'avaient jamais été exécutées.

| Étape | Résultat |
|---|---|
| TP 08 §7 — provoquer un échec d'idempotence | **conforme** — une tâche `command` nue ajoutée au rôle fait échouer Molecule : `CRITICAL Idempotence test failed because of the following tasks`. Le tag d'exemption est `molecule-idempotence-notest`. |
| TP 09 §5 — exécuter le fil rouge dans l'EE | **conforme** via `ansible-navigator` : `changed=0` sur les 4 VM. Voir la réserve ci-dessous. |
| TP 09 §6 — retirer une collection du fichier | **conforme** — l'EE se construit toujours, mais le fil rouge échoue en `rc=4` : `couldn't resolve module/action 'community.postgresql.postgresql_user'`. |
| TP 10 §8 — `ansible-vault rekey` | **conforme** — `Rekey successful`, l'identifiant `dev` reste inscrit dans l'en-tête, l'ancien mot de passe est rejeté (`rc=1`). |
| TP 13 §4 — comparer `merged` et `overridden` | **l'exercice ne démontrait rien** — voir ci-dessous. |

**TP 13 §4.** Sur un lab fraîchement monté, les deux états produisent des commandes
**identiques** : `overridden` ne supprime que ce qui existe hors de la configuration fournie, et
il n'y a rien. L'énoncé demandait pourtant d'« observer ce que le second supprimerait ». Il faut
d'abord poser un attribut hors périmètre ; la différence apparaît alors :

```yaml
overridden:
  - delete interfaces ethernet eth0 description      # <- absent de merged
```

L'énoncé porte désormais l'étape préparatoire.

**TP 09 §5 — réserve sur la commande documentée.** Telle qu'écrite dans le README
(`ansible-navigator run site.yml --eei formation-ee:1.0 -m stdout`), la commande sort en
**exit 0 sans rien exécuter** quand on la lance sur le corrigé : l'`ansible.cfg` du dépôt pointe
vers l'inventaire du *stagiaire*, absent. Il faut ajouter `-i`. Un exit 0 qui n'exécute rien est
un piège. Par ailleurs, lancer l'EE avec `podman run` **brut** ne fonctionne pas sans travail
supplémentaire : l'uid du conteneur ne peut pas lire les clés Vagrant
(`Load key ... Permission denied`), là où `ansible-navigator` gère ce montage.

## 3.4 Une affirmation du corrigé infirmée : les états hors ligne

Le TP 13 affirmait que `rendered` et `parsed` sont inutilisables sans équipement, avec ce
tableau :

| Tentative | Résultat annoncé |
|---|---|
| `connection: local` | `Connection type local is not valid for this module` |
| `ansible_connection: network_cli` | `ssh connect failed: Timeout connecting to ...` |

**La première ligne est exacte, la seconde est fausse.** Mesuré avec `vyos.vyos` 6.0 sur
`ansible-core` 2.21, contre `203.0.113.254` (TEST-NET-3, injoignable) : `rendered` aboutit en
**1,1 s**, sans ouvrir de session SSH, et retourne les bonnes commandes.

La contrainte porte donc sur le **type de connexion déclaré**, pas sur l'existence de
l'équipement : il suffit de déclarer `network_cli`.

Le piège qui a probablement produit l'affirmation d'origine — et dans lequel je suis tombé au
premier essai : une variable d'inventaire `ansible_connection` **l'emporte** sur le mot-clé
`connection:` du play. Un play déclarant `connection: local` sur un hôte dont l'inventaire porte
`ansible_connection: network_cli` utilise en réalité `network_cli`. On croit tester le mode
local alors qu'on parle à l'équipement, et on en tire la conclusion inverse.

---

## 4. Ce qui n'a pas pu être testé

| Sujet | TP | Raison |
|---|---|---|
| Provisioning Proxmox et vSphere réel | 12 | aucun hyperviseur — **assumé** : le module est désormais annoncé comme théorique (voir §6) |
| Molecule dans un exécuteur de CI | 09 | aucun exécuteur GitLab ni GitHub self-hosted |
| Molecule en exécuteur de CI conteneurisé | 09 | conteneurs imbriqués, aucun exécuteur disponible |
| Usage de l'interface Semaphore | 11 | création de projet, clés, tâches, webhook : manipulation en salle |
| NetBox comme source de vérité | 13 | aucune instance NetBox |
| `parsed` hors ligne | 13 | seul `rendered` a été éprouvé (§3.4) |
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

### Décision prise : Proxmox et VMware restent théoriques

Aucun hyperviseur ne sera fourni. Le support l'annonçait mal — il promettait une « démonstration
formateur sur un Proxmox réel » et PLAN.md prévoyait « un accès lecture à un Proxmox VE 9.x de
démo ». Ces promesses sont supprimées : le module 13, le TP 12 et le corrigé indiquent désormais
explicitement que la partie est théorique, que le code n'a jamais tourné contre un hyperviseur,
et ce qui a malgré tout été vérifié. Un formateur préparant la session ne cherchera plus à
fournir un accès qui n'existe pas.

### À faire avant la session

1. **Miroiter les trois boxes** (`bento/debian-13`, `bento/rockylinux-10`, `vyos/current`) et
   les servir en interne avec `box_url` + `box_download_checksum`. Le registre HCP Vagrant
   ferme le **31 décembre 2026** : sans cela, le lab devient indémarrable. C'est le seul
   risque qui rend la formation impossible à donner.
2. **Prévoir un miroir apt local**, ou accepter que la première tâche de chaque playbook
   rafraîchisse le cache. La combinaison box épinglée + point release Debian fait disparaître
   des `.deb` du miroir : c'est la cause de **trois** des bugs bloquants rencontrés.
3. **Dérouler le lab une fois de bout en bout, sur le poste de la salle**, une semaine avant.
   Compter **28 minutes** d'exécution machine pour les 14 TP, hors téléchargements — mesuré lors
   de la passe à froid (§2.1). Cette passe a été faite ici et ne révèle plus aucun échec ; la
   refaire sur la machine de la salle reste utile, car elle éprouve le réseau et le compte de
   cette machine-là, pas les miens.
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
