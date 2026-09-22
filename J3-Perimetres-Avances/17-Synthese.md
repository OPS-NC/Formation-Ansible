# Module 17 — Synthèse et feuille de route

> **Jour 3** · 45 min · Synthèse et clôture
> Prérequis : l'ensemble de la formation.

## Objectifs

- Relire le parcours accompli et ce qu'il produit.
- Disposer d'une checklist de mise en production.
- Savoir par quoi commencer en rentrant.

---

## 1. Ce qui a été construit

Un projet unique, du premier au dernier TP :

```
TP 01-02   nœud de contrôle, inventaire structuré sur deux axes
TP 03-05   playbook multi-OS, gabarits, handlers, rôles, collections
TP 06-08   orchestration par vagues, inventaire construit, lint et Molecule
TP 09-11   chaîne d'intégration, execution environment, secrets, interface web
TP 12-14   provisioning, réseau, cluster Kubernetes
```

Le résultat n'est pas une collection d'exemples : c'est un dépôt qui passe `ansible-lint` au
profil `production`, dont les rôles sont testés sur deux distributions, dont les secrets sont
chiffrés, et qui s'exécute aussi bien depuis un poste, depuis une chaîne d'intégration que
depuis une interface web.

## 2. Les idées qui structurent tout le reste

**Piloter par les données, pas par le code.** Ajouter un site, une machine ou un équipement doit
consister à ajouter des variables, jamais des tâches. C'est le fil conducteur des modules 05, 06
et 13.

**Une différence de valeur va dans les variables de groupe ; une différence de mécanisme se
normalise explicitement.** Le module 04 pose la règle, le module 07 montre son exception
légitime.

**L'idempotence est portée par les modules, pas par le moteur.** `command` et `shell` doivent
être encadrés. Molecule en fait un test automatique.

**Ce qui n'est pas déclaré n'existe pas.** Une collection absente de `collections/requirements.yml`
fait échouer `ansible-lint`, la chaîne d'intégration et la construction de l'execution
environment. La déclaration des dépendances n'est pas de la paperasse.

**Vérifier avant d'appliquer.** `--check --diff` transforme un playbook en outil d'audit de
conformité, exécutable sans risque.

## 3. Checklist d'un projet en production

### Structure
- [ ] `ansible.cfg` versionné, `inventory` et `roles_path` explicites
- [ ] Un inventaire par environnement, un seul `site.yml`
- [ ] Variables dans `group_vars/` et `host_vars/`, à côté de l'inventaire
- [ ] Rôles préfixés, `defaults/` pour ce qui se surcharge, `vars/` pour le reste
- [ ] `meta/argument_specs.yml` sur les rôles partagés

### Dépendances
- [ ] `collections/requirements.yml` complet et **épinglé**
- [ ] Contenu externe évalué sur sa **matrice de CI**, pas sur ses métadonnées
- [ ] Execution environment construit et publié

### Qualité
- [ ] `ansible-lint` au profil `production`, zéro violation
- [ ] `warn_list` justifié, `skip_list` documenté
- [ ] Scénario Molecule par rôle, sur les distributions réellement utilisées
- [ ] Test d'idempotence automatisé
- [ ] `pre-commit` installé sur tous les postes

### Sécurité
- [ ] Aucun secret en clair, `main.yml` en clair et `vault.yml` chiffré
- [ ] Un mot de passe de vault **par environnement**
- [ ] `.vault_pass*` dans `.gitignore`, hook `detect-private-key` actif
- [ ] `no_log: true` sur les tâches manipulant des secrets
- [ ] `host_key_checking` actif, `StrictHostKeyChecking=accept-new`
- [ ] Compte de service dédié, droits minimaux
- [ ] Nœud de contrôle traité comme un bastion

### Exploitation
- [ ] Chaîne d'intégration : lint, tests, simulation, déploiement manuel sur étiquette
- [ ] `serial` et `max_fail_percentage` sur les opérations de parc
- [ ] Remise en état dans `always`, jamais dans `block`
- [ ] Sauvegarde avant modification sur les équipements réseau
- [ ] Journal des exécutions conservé

## 4. Par où commencer en rentrant

Dans cet ordre, chaque étape rendant la suivante possible.

1. **Inventorier l'existant.** Écrire l'inventaire du parc réel, sur deux axes. Ne rien
   automatiser encore. `ansible all -m ping` et un audit ad hoc suffisent à créer de la valeur
   et à révéler les surprises.

2. **Choisir un gain rapide.** Une tâche répétitive, sans risque, faite à la main aujourd'hui :
   création de comptes, déploiement d'une clé SSH, collecte d'inventaire matériel. Un playbook
   court qui fonctionne convainc plus qu'une architecture cible.

3. **Mettre le dépôt sous qualité dès le premier jour.** `ansible-lint` et `pre-commit` coûtent
   une heure à installer et évitent des mois de dette. Les ajouter après coup est douloureux.

4. **Déclarer les dépendances**, même si le paquet `ansible` suffit sur votre poste.

5. **Chiffrer les secrets** avant qu'il y en ait beaucoup.

6. **Automatiser la vérification** avant d'automatiser le déploiement. Une chaîne qui lance
   `--check --diff` chaque nuit détecte la dérive sans rien risquer.

7. **Ajouter une interface web** quand plusieurs personnes exécutent, ou quand il faut tracer.
   Pas avant.

## 5. Ce qui change en 2026 : à retenir

| Sujet | État |
|---|---|
| `ansible-core` 2.21 / Ansible 14 | Python 3.12+ sur le contrôleur, 3.9+ sur les cibles |
| `paramiko_ssh` | Supprimé, aucune collection ne le reprend |
| `stdout_callback = yaml` | Mort ; utiliser `callback_result_format = yaml` |
| `apt_key`, `apt_repository` | Dépréciés au profit de `deb822_repository` |
| Molecule | Format **ansible-native** depuis la 25.9 |
| AWX | **Gelé depuis juillet 2024** |
| AAP 2.7 | Conteneurisé uniquement |
| `junipernetworks.junos` | Archivée, remplacée par `juniper.device` |
| `community.vmware.vmware_vm_inventory` | Déprécié, migrer vers `vmware.vmware.vms` |
| `community.postgresql` 5.0 | Alias `db`, `port`, `login` supprimés |
| Registre de boxes Vagrant | **Ferme le 31 décembre 2026** |
| Lightspeed | Renommé « Automation coding assistant », modèle au choix |

## 6. Pour continuer

**Documentation**
- Documentation officielle Ansible, qui suit la version installée
- `ansible-doc` en local : toujours plus fiable qu'une recherche web
- Bonnes pratiques Red Hat CoP, « Good Practices for Ansible »
- Forum de la communauté Ansible

**Certification**
La certification Red Hat **EX294 (RHCE)** est un examen pratique de trois heures sur RHEL :
inventaires, playbooks, rôles, vault, gestion de systèmes. Les modules 01 à 06 et 11 en couvrent
l'essentiel. Elle n'aborde ni CI/CD, ni réseau, ni Kubernetes.

**Aller plus loin**
- Écrire une collection interne et la publier sur un hub privé
- Event-Driven Ansible sur un cas de remédiation réel
- NetBox comme source de vérité d'un parc réseau
- Contribuer à une collection communautaire

---

## Quiz final

20 minutes, correction collective.

1. Un playbook fonctionne sur votre poste mais échoue en CI avec `couldn't resolve
   module/action`. Quelle est la cause la plus probable ?
2. Pourquoi `--check` n'exécute-t-il pas les tâches `command` ? Comment forcer une tâche de
   lecture à s'exécuter quand même ?
3. Deux groupes du même niveau définissent la même variable. Lequel gagne, et comment rendre ce
   choix explicite ?
4. Vous devez mettre à jour 40 serveurs web sans interruption de service. Quelles directives
   utilisez-vous ?
5. Où placer la remise en rotation d'un serveur après une opération risquée, et pourquoi ?
6. Un rôle Galaxy annonce le support de Rocky Linux 10 dans `meta/main.yml`. Que vérifiez-vous
   avant de l'adopter ?
7. Quelle est la différence pratique entre `merged` et `overridden` sur un équipement réseau ?
8. Vos trois nœuds Kubernetes affichent la même adresse interne. Quelle est la cause ?
9. Citez deux limites d'`ansible-vault` que SOPS ou un coffre externe corrigent.
10. Un assistant IA vous propose `stdout_callback: yaml`. Que répondez-vous ?

## Auto-positionnement

Reprenez les dix objectifs du [plan de formation](../PLAN.md#1-objectifs-pédagogiques) et
notez-vous de 1 à 4 : *découvert*, *compris*, *sais faire avec la documentation*, *autonome*.
Les objectifs notés 1 ou 2 indiquent où porter votre effort dans les semaines qui viennent.

---

**Module précédent :** [16 — Event-Driven, IA, Windows](16-EDA-IA-Windows.md)
**Retour au parcours :** [README](../README.md)
