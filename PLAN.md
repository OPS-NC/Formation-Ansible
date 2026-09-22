# Formation Ansible — Administration avancée de serveurs, provisioning, réseau et Kubernetes

**Durée :** 3 jours (21 h de face-à-face, 7 h/jour)
**Niveau :** administrateurs systèmes Linux confirmés, DevOps, ingénieurs infrastructure
**État de l'art :** septembre 2026 (ansible-core 2.21 / paquet communautaire Ansible 14)
**Environnement de lab :** poste Ubuntu 26.04 LTS (nœud de contrôle) + VMs Debian 13 « Trixie » et Rocky Linux 10 sous Vagrant / VirtualBox

> Ce document décrit la **structure** de la formation : objectifs, découpage horaire, contenu de chaque module, emplacements et intentions des travaux pratiques (TP). Les énoncés et corrigés des TP font l'objet de livrables séparés.

---

## 1. Objectifs pédagogiques

À l'issue de la formation, le stagiaire est capable de :

1. Installer et configurer un nœud de contrôle Ansible moderne (pipx, versions figées, execution environments) et administrer un parc hétérogène Debian / RHEL-like.
2. Écrire des playbooks, rôles et collections **idempotents**, testés (ansible-lint, molecule) et conformes aux bonnes pratiques Red Hat CoP.
3. Structurer un projet Ansible dans Git et l'intégrer à une chaîne CI/CD (GitLab CI, GitHub Actions, pre-commit).
4. Réutiliser du contenu existant (Galaxy, collections certifiées / communautaires, hub privé) et publier le sien.
5. Gérer les secrets à l'échelle (ansible-vault, SOPS/age, OpenBao/HashiCorp Vault).
6. Déployer et exploiter une interface web gratuite (Semaphore UI) et positionner AWX / Red Hat Ansible Automation Platform (AAP).
7. Comprendre le provisioning de VMs avec Ansible sur Proxmox VE et VMware vSphere, et son articulation avec Terraform/OpenTofu.
8. Comprendre l'automatisation réseau (switchs / routeurs) : plugins de connexion, resource modules, collections vendeurs, source de vérité NetBox.
9. Utiliser Ansible autour de Kubernetes : bootstrap de cluster, day-2 ops, collection `kubernetes.core`, positionnement face à Helm / ArgoCD / Flux.
10. Situer les évolutions 2026 : Event-Driven Ansible, assistants IA / MCP, Windows via SSH.

---

## 2. Public, prérequis et évaluation

### Public
- Administrateurs Linux (Debian/Ubuntu et RHEL/Rocky/Alma), 2 ans d'expérience minimum.
- Ingénieurs DevOps / SRE souhaitant industrialiser la configuration.
- Administrateurs virtualisation / réseau curieux d'automatiser (modules J3 volontairement plus théoriques).

### Prérequis stagiaires
- Aisance en ligne de commande Linux, SSH, sudo, systemd, gestion de paquets apt / dnf.
- Notions YAML et Git (clone, commit, branche). Une remise à niveau Git de 30 min est prévue J2.
- Aucune connaissance préalable d'Ansible requise, mais le rythme du J1 est soutenu.

### Évaluation
- Quiz de positionnement en début de J1 (15 min).
- TP fil rouge évalués en continu (auto-évaluation + validation formateur).
- Quiz final J3 (20 min) et fiche d'auto-positionnement sur les 10 objectifs.
- Optionnel : préparation à la certification Red Hat **EX294 (RHCE)** évoquée en clôture.

---

## 3. Environnement technique

### 3.1 Architecture du lab (fil rouge des 3 jours)

Chaque stagiaire dispose d'un poste Ubuntu 26.04 LTS avec VirtualBox et Vagrant. Le poste **est** le nœud de contrôle. Toutes les cibles sont définies dans un **unique `Vagrantfile`** : aucune machine n'est créée à la main ni depuis une ISO.

| VM | IP | Box | Rôle dans le fil rouge | RAM / vCPU |
|---|---|---|---|---|
| `web01` | 192.168.56.11 | `bento/debian-13` | Serveur web (nginx), cible J1/J2 | 1024 Mo / 1 |
| `web02` | 192.168.56.12 | `bento/debian-13` | Serveur web (nginx), cible J1/J2 | 1024 Mo / 1 |
| `db01` | 192.168.56.21 | `bento/rockylinux-10` | PostgreSQL, cible multi-distribution J1/J2 | 2048 Mo / 2 |
| `tools` | 192.168.56.31 | `bento/debian-13` | Semaphore UI, exécution CI — J2 | 2048 Mo / 2 |
| `k3s-master` | 192.168.56.41 | `bento/debian-13` | Plan de contrôle k3s — J3 | 2048 Mo / 2 |
| `k3s-node01` | 192.168.56.42 | `bento/debian-13` | Nœud de calcul k3s — J3 | 1536 Mo / 2 |
| `k3s-node02` | 192.168.56.43 | `bento/debian-13` | Nœud de calcul k3s — J3 | 1536 Mo / 2 |

Les trois VMs du cluster k3s sont déclarées `autostart: false` : `vagrant up` ne démarre que le lab J1/J2 (4 VMs, environ 6 Go). Le cluster est monté au jour 3 par `vagrant up k3s-master k3s-node01 k3s-node02` (3 VMs, environ 5 Go). Un troisième worker est disponible en commentaire dans le `Vagrantfile` pour les postes disposant de 32 Go.

Réseau host-only `192.168.56.0/24`. La résolution de noms est assurée par un `/etc/hosts` généré par Ansible (TP 03). Le lab réseau du module 14 **utilise une VM** : le routeur VyOS `net01`, piloté en `network_cli` (validé contre l'équipement réel). En revanche, **aucun hyperviseur Proxmox ni vSphere n'est fourni** : le module 13 est théorique et ne comporte pas de démonstration sur infrastructure réelle.
### 3.2 Choix techniques et points d'attention (vérifiés septembre 2026)

- **Ansible :** cible **ansible-core 2.21.4 / Ansible 14.4**, installé via trois commandes `pipx` à versions figées (`ansible==14.4.*`, `ansible-lint==26.8.*`, `molecule==26.8.*`). `ansible-builder` et `ansible-navigator` s'ajoutent au module 10, `ansible-dev-tools` restant une alternative tout-en-un non retenue. Les dépôts Ubuntu 26.04 (core 2.20.1), Debian 13 (core 2.19.4, EOL 30 nov. 2026) et Rocky 10 (core 2.16.16, EOL upstream mais maintenu par RHEL 10) sont volontairement écartés pour le nœud de contrôle. Python contrôleur : 3.12–3.14 (Ubuntu 26.04 fournit 3.14). Python cibles : 3.9–3.14 (Debian 13 : 3.13 ; Rocky 10 : 3.12).
- **Outillage :** ansible-lint 26.8, molecule 26.8, ansible-builder 3.1 et ansible-navigator 26.8 (modules 09 et 10), extension VS Code `redhat.ansible` 26.8, image conteneur `ghcr.io/ansible/community-ansible-dev-tools` pour la CI.
- **Vagrant 2.4.9** (licence BSL, dépôt apt HashiCorp car Ubuntu ne le package plus depuis 24.04) + **VirtualBox 7.2.x**. Vérifier avant la session la compatibilité des modules noyau VirtualBox avec le noyau 7.x d'Ubuntu 26.04 (problèmes signalés avril–mai 2026) ; plan B : provider `vagrant-libvirt` (KVM).
- **Boxes :** `bento/debian-13` et `bento/rockylinux-10` (providers VirtualBox disponibles). `debian/trixie64` officielle n'existe qu'en libvirt ; `generic/rocky10` n'existe pas ; `rockylinux/10` officielle est figée en 10.0.
- **Dépréciation HCP Vagrant Registry :** plus de nouvelles boxes après le 1er oct. 2026, fin de support 2 nov. 2026, décommission 31 déc. 2026. **Les boxes doivent être pré-téléchargées** et servies depuis un dépôt local (`vagrant box add` depuis fichier `.box` + metadata JSON) fourni sur clé USB / partage réseau.
- **Rocky Linux 10 :** exige un CPU **x86-64-v3** (AVX2, hôte Haswell ou plus récent) et un **boot UEFI** (activer EFI dans VirtualBox, type « Red Hat 10.x »). À vérifier sur le parc de postes de formation.
- **Connectivité :** Galaxy (`galaxy.ansible.com`) a connu des indisponibilités début 2026. Prévoir un cache local des collections (`ansible-galaxy collection download`) et des images conteneur nécessaires.
- **Semaphore UI 2.19.x** (MIT) installé par paquet `.deb` + SQLite : opérationnel en 15 min sans Kubernetes. **AWX 24.6.1** (juillet 2024) est présenté comme projet gelé et démontré uniquement par le formateur (k3s, 8 Go).

### 3.3 Kit formateur (à préparer avant J1)
- Dépôt de boxes local et miroir de collections / images conteneur.
- Dépôt Git de référence (`formation-ansible`) avec les branches par TP, hébergé sur une instance GitLab CE ou Gitea locale (ou GitHub si Internet fiable).
- Instance de démo : Semaphore UI (installé par le TP 11 sur la VM `tools`), AWX sur k3s (démo J2 facultative).
- **Proxmox et vSphere : rien à préparer, la partie est théorique.** Aucun accès à un hyperviseur n'est requis ni prévu. Des captures d'écran commentées suffisent ; à défaut, la lecture du code des corrigés est l'exercice.
- Partie réseau : **pas de Containerlab**, le routeur VyOS `net01` du `Vagrantfile` suffit et a été validé.
- Support de cours (slides), fiches mémo (cheat sheets) : CLI, structure de projet, profils ansible-lint, états des resource modules.

---

## 4. Vue d'ensemble

| Jour | Thème | Répartition |
|---|---|---|
| **J1** | Socle Ansible : du nœud de contrôle aux rôles et collections | 55 % théorie / 45 % TP |
| **J2** | Administration avancée, qualité, Git / CI-CD, secrets, WebUI | 45 % théorie / 55 % TP |
| **J3** | Au-delà du serveur : provisioning, réseau, Kubernetes, EDA / IA, clôture | 70 % théorie / 30 % démo + TP |

Fil conducteur : un projet Git unique `formation-ansible` que les stagiaires font évoluer du J1 au J3 (inventaire → playbooks → rôles → collection → CI → exécution via Semaphore → déploiement d'une application sur k3s).

---

## 5. Jour 1 — Socle Ansible et gestion de configuration

### Module 1.1 — Introduction et positionnement (9h00–9h45, 45 min)
- Accueil, tour de table, quiz de positionnement.
- Pourquoi Ansible en 2026 : agentless, push, idempotence, déclaratif vs impératif.
- Écosystème et vocabulaire : ansible-core vs paquet communautaire Ansible (14 = core 2.21), collections, Galaxy, Red Hat AAP, versionnement calendaire de l'outillage (26.x).
- Cycle de release (2 majeures/an, mai et novembre), matrice de support Python contrôleur / cibles, EOL.
- Positionnement face à Puppet / Salt / Chef, et face à Terraform / OpenTofu (introduction, approfondi J3).
- Carte de la formation et présentation du fil rouge.

### Module 1.2 — Nœud de contrôle et lab (9h45–10h45, 60 min)
- Installation moderne : `pipx` / `uv tool` + `ansible-dev-tools`. Pourquoi ne pas utiliser les paquets distribution (versions en retard, EOL).
- Tour des binaires : `ansible`, `ansible-playbook`, `ansible-inventory`, `ansible-galaxy`, `ansible-vault`, `ansible-doc`, `ansible-config`, `ansible-console`, `ansible-navigator`, `ansible-lint`.
- `ansible.cfg` : précédence, options clés (inventory, remote_user, private_key_file, pipelining, forks, callbacks, interpreter_python).
- Prérequis côté cibles : SSH, Python, sudo ; découverte de l'interpréteur ; cas Rocky 10 / Debian 13.
- Vagrant et VirtualBox : `Vagrantfile` multi-machines, provisioner `ansible` vs `ansible_local`, réseau privé, snapshots.
- **TP 1 — Mise en place du lab (30 min)** : lancer les 4 VMs depuis le `Vagrantfile` fourni, installer ansible-dev-tools, premier `ansible -m ping` sur toutes les cibles, `ansible-navigator` en mode stdout.

*Pause 10h45–11h00*

### Module 1.3 — Inventaire et commandes ad hoc (11h00–12h00, 60 min)
- Inventaire INI vs YAML, groupes, groupes de groupes, `all` / `ungrouped`, variables d'hôte et de groupe.
- Arborescence `inventories/<env>/` avec `host_vars/` et `group_vars/`, séparation dev / prod.
- Précédence des variables (22 niveaux résumés en 5 règles pratiques), variables magiques (`hostvars`, `groups`, `inventory_hostname`, `ansible_facts`).
- Patterns de ciblage, `--limit`, `--list-hosts`, `ansible-inventory --graph`.
- Commandes ad hoc : modules `command` / `shell` / `raw` vs modules idempotents ; devenir root avec `become`.
- Introduction aux inventaires dynamiques (plugins), approfondis J2.
- **TP 2 — Inventaire du fil rouge (25 min)** : inventaire YAML `dev` avec groupes `web`, `db`, `tools`, par OS (`debian`, `rocky`), variables de groupe ; audit ad hoc du parc (uptime, version d'OS, paquets).

### Module 1.4 — Playbooks : fondamentaux (12h00–12h30 puis 13h30–14h15, 75 min)
- Structure d'un playbook : plays, tasks, `hosts`, `become`, `gather_facts`, `vars`.
- Modules incontournables via FQCN (`ansible.builtin.*`) : `package` / `apt` / `dnf`, `service` / `systemd_service`, `copy`, `template`, `file`, `lineinfile`, `blockinfile`, `user`, `group`, `authorized_key`, `git`, `get_url`, `unarchive`, `stat`, `command` avec `creates` / `removes`.
- Idempotence : `changed`, `ok`, `failed`, `skipped` ; `changed_when` / `failed_when` ; `check_mode` (`--check`) et `--diff`.
- Facts : `setup`, `gather_subset`, facts personnalisés (`/etc/ansible/facts.d`), cache de facts.
- `ansible-doc` et la documentation en ligne ; `ansible-lint` en fil rouge dès le premier playbook.
- **TP 3 — Premier playbook multi-OS (35 min)** : configuration de base commune (hostname, `/etc/hosts` généré, paquets utilitaires, utilisateur d'administration, clé SSH, timezone, NTP/chrony) sur Debian 13 et Rocky 10 avec gestion des différences de distribution.

*Déjeuner 12h30–13h30*

### Module 1.5 — Variables, Jinja2, templates, handlers (14h15–15h30, 75 min)
- Variables : définition dans le play, `vars_files`, `set_fact`, `register`, variables d'extra (`-e`), variables d'environnement.
- Jinja2 : expressions, filtres essentiels (`default`, `mandatory`, `join`, `map`, `select`, `selectattr`, `dict2items`, `to_nice_yaml`, `regex_replace`, `ipaddr` via `ansible.utils`), tests, boucles et conditions dans les templates.
- Conditions `when`, boucles `loop` / `loop_control`, `with_*` legacy, `until` / `retries`.
- Handlers : `notify`, `listen`, `meta: flush_handlers`, pièges (handler non déclenché en cas d'échec, `force_handlers`).
- Templates : `template` avec `validate`, `backup`, gestion des permissions, en-tête `ansible_managed`.
- Nouveautés 2.19–2.21 à connaître : moteur de templating refondu (« data tagging »), `register` vers plusieurs variables (2.21), avertissements de conversion de types.
- **TP 4 — Déploiement nginx templatisé (40 min)** : rôle web sur `web1`/`web2` avec template de vhost, variables par hôte, handler de rechargement, validation de configuration, vérification en `--check --diff` puis idempotence (second run sans `changed`).

*Pause 15h30–15h45*

### Module 1.6 — Rôles, collections et réutilisation de contenu (15h45–17h00, 75 min)
- Rôles : arborescence (`tasks`, `handlers`, `defaults`, `vars`, `files`, `templates`, `meta`, `argument_specs`), `roles:` vs `include_role` / `import_role`, dépendances, validation des arguments (`meta/argument_specs.yml`).
- `ansible-creator init` pour scaffolder, conventions de nommage (Red Hat CoP « Good Practices for Ansible »).
- Collections : namespace, `galaxy.yml`, structure, FQCN, `ansible_collections/`, `collections/requirements.yml`, `ansible-galaxy collection install / list / download`.
- Galaxy en 2026 : collections vs rôles legacy, contenu communautaire vs **certifié** (Automation Hub) vs **validé**, hub privé (galaxy_ng / Pulp), signatures GPG, page de statut communautaire.
- **Réutiliser du contenu existant** : évaluer une collection ou un rôle (activité, tests, `requires_ansible`, changelog, licence), collections système incontournables (`ansible.posix`, `community.general`, `community.crypto`, `community.mysql` / `community.postgresql`, `ansible.utils`), rôles de référence (geerlingguy, Debops, robertdebock) et comment les surcharger sans les forker.
- **TP 5 — Rôle base de données réutilisé (35 min)** : installer PostgreSQL sur `db1` (Rocky 10) via une collection communautaire (`community.postgresql`) et un rôle Galaxy, épinglé dans `requirements.yml`, puis créer base, utilisateur et règle `pg_hba` ; convertir le rôle web du TP 4 vers l'arborescence standard.

### Synthèse J1 (17h00–17h15)
- Récapitulatif, questions, checkpoint du dépôt Git fil rouge (tag `j1`).
- Devoir facultatif : lire la page « Zen of Ansible » et le profil `basic` d'ansible-lint.

---

## 6. Jour 2 — Administration avancée, qualité, Git / CI-CD, secrets et interfaces web

### Module 2.1 — Contrôle avancé de l'exécution (9h00–10h15, 75 min)
- Rappels J1 et correction du devoir (10 min).
- Blocs : `block` / `rescue` / `always`, gestion des erreurs, `ignore_errors`, `any_errors_fatal`, `max_fail_percentage`.
- Délégation et orchestration : `delegate_to`, `run_once`, `delegate_facts`, `local_action`, `serial`, `order`, `throttle`.
- Stratégies : `linear`, `free`, `host_pinned`, `debug` ; `forks`, `pipelining`, `mitogen` (mention historique), mesure de performance (callbacks `profile_tasks`, `timer`).
- Tâches asynchrones : `async` / `poll`, `async_status`, redémarrage de nœud avec `ansible.builtin.reboot` et `wait_for_connection`.
- Tags, `--start-at-task`, `--step`, `ansible-playbook --list-tasks`, `import_*` vs `include_*` (statique vs dynamique).
- Gestion des différences multi-OS : `ansible_facts['os_family']`, `vars_files` conditionnels avec `first_found`, `package` générique vs modules spécifiques.
- Plugins utiles : lookups (`file`, `env`, `pipe`, `template`, `first_found`, `password`), filtres `community.general`, callbacks (`yaml`, `json`, `junit`), `ansible.builtin.debug` avec `verbosity`.
- **TP 6 — Mise à jour orchestrée du parc (35 min)** : patching en `serial`, sortie / entrée de rotation des serveurs web (fichier de maintenance), redémarrage conditionnel si noyau mis à jour, rapport JSON final, gestion de l'échec sur un hôte.

*Pause 10h15–10h30*

### Module 2.2 — Inventaires dynamiques et infrastructure à grande échelle (10h30–11h15, 45 min)
- Plugins d'inventaire : `auto`, `yaml`, `ini`, `constructed`, `script`, composition (`compose`, `keyed_groups`, `groups`), `inventory.yml` multi-sources.
- Sources courantes : `community.libvirt.libvirt`, `community.proxmox.proxmox`, `vmware.vmware.vms`, `amazon.aws.aws_ec2`, `netbox.netbox.nb_inventory`, `cloud.terraform.terraform_state` (introduction, détail J3).
- Cache d'inventaire et de facts (`jsonfile`, `redis`), `ansible-inventory --list`.
- Gestion de plusieurs environnements : arborescence par environnement vs par stade, variables partagées, promotion de versions.
- Sécurité et exploitation : `become` fin (`become_user`, `become_method`), bastion / ProxyJump, `ansible_ssh_common_args`, connexion `ssh` vs `paramiko` vs `libssh`, agent forwarding, comptes de service.
- **TP 7 — Inventaire construit (20 min)** : plugin `constructed` générant des groupes par OS, par rôle et par « rang de maintenance », avec cache de facts.

### Module 2.3 — Qualité : ansible-lint, molecule, tests (11h15–12h30, 75 min)
- Bonnes pratiques Red Hat CoP : structure, nommage, « Zen of Ansible », checklist de revue de code.
- **ansible-lint 26.x** : profils `min` → `basic` → `moderate` → `safety` → `shared` → `production`, fichier `.ansible-lint`, `skip_list` / `warn_list`, `# noqa` ciblé, auto-fix (`--fix`), règles emblématiques (`fqcn`, `name[casing]`, `no-changed-when`, `risky-file-permissions`, `yaml[...]` via yamllint).
- **molecule 26.x** : scénarios, `molecule.yml`, drivers `podman` / `docker` / `vagrant` (via molecule-plugins), séquences `create` → `converge` → `idempotence` → `verify` → `destroy`, vérificateur `ansible` par défaut, `pytest-testinfra`, `--workers`.
- Tests de collections : `ansible-test sanity / units / integration`.
- Autres filets : `ansible-playbook --syntax-check`, `--check --diff` comme test de non-régression, `argument_specs`, `assert` / `validate` (`ansible.utils.validate` avec JSON Schema).
- Extension VS Code `redhat.ansible` (LSP, lint intégré, devcontainer).
- **TP 8 — Mise sous qualité du rôle web (35 min)** : `.ansible-lint` profil `production`, correction des écarts, scénario molecule podman avec Debian 13 et Rocky 10, test d'idempotence, vérification testinfra.

*Déjeuner 12h30–13h30*

### Module 2.4 — Git et CI/CD autour d'Ansible (13h30–15h00, 90 min)
- Remise à niveau Git ciblée (15 min) : branches courtes, merge / pull request, tags SemVer, `.gitignore` Ansible (`*.retry`, `.vault_pass`, `collections/ansible_collections/`).
- Organisation des dépôts : monorepo d'infrastructure (`inventories/`, `playbooks/`, `roles/`, `collections/requirements.yml`, `ansible.cfg`) vs dépôt par collection ; gestion des dépendances épinglées ; politique de branches et revue obligatoire.
- Pre-commit : hooks `yamllint` et `ansible-lint`, formatage.
- **GitLab CI** : pipeline en étapes `lint` → `test` (molecule avec podman ou docker:dind) → `check` (`ansible-playbook --check --diff` sur `dev`) → `deploy` (manuel, sur tag) ; image `community-ansible-dev-tools` ou execution environment maison ; runner et accès SSH aux cibles ; artefacts et rapports JUnit.
- **GitHub Actions** : action officielle `ansible/ansible-lint@v26`, `ansible-community/ansible-test-gh-action` pour les collections, matrices de versions.
- Secrets en CI : variables masquées → `vault_password_file` scripté, comptes de service SSH, OIDC vers un coffre (introduction, détail module 2.5).
- Publication : `ansible-galaxy collection build / publish`, hub privé galaxy_ng, `ansible-sign` pour signer les projets.
- **Execution environments** : pourquoi (reproductibilité contrôleur / CI / WebUI), `execution-environment.yml` v3, `ansible-builder`, `ansible-navigator --eemode`, `ansible-runner` (utilisé par AWX/AAP et comme job conteneurisé).
- GitOps pour la configuration : le dépôt Git comme source de vérité, déclenchement par webhook, lien avec la WebUI (module 2.6).
- **TP 9 — Pipeline CI du projet fil rouge (40 min)** : pre-commit + pipeline GitLab CI (ou GitHub Actions selon la plateforme retenue) exécutant lint, molecule et `--check` sur `dev` ; construction d'un execution environment minimal contenant les collections du projet et exécution du playbook avec `ansible-navigator`.

*Pause 15h00–15h15*

### Module 2.5 — Gestion des secrets à l'échelle (15h15–16h00, 45 min)
- `ansible-vault` : chiffrement de fichiers vs `encrypt_string`, multi-vault-id, rotation (`rekey`), `--vault-password-file`, intégration éditeur, limites (diff opaque, partage du mot de passe).
- **SOPS + age** avec `community.sops` : chiffrement par valeur, diffs lisibles en revue, `sops_lookup`, `load_vars`, clés par environnement.
- Coffres externes : `community.hashi_vault` compatible **OpenBao** (AppRole, JWT/OIDC depuis la CI ou Semaphore/AAP), `community.general.bitwarden_secrets_manager`, `onepassword`, secrets managers cloud.
- Hygiène : `no_log`, `hide_sensitive`, éviter les secrets dans les facts et les logs de CI, rotation des clés SSH, principe du moindre privilège pour les comptes d'automatisation.
- **TP 10 — Secrets du fil rouge (20 min)** : migrer les mots de passe PostgreSQL vers `ansible-vault` (multi-vault-id dev/prod), puis vers SOPS/age ; démonstration formateur d'un lookup OpenBao.

### Module 2.6 — Interfaces web : gratuites et payantes (16h00–17h00, 60 min)
- Pourquoi une WebUI : RBAC, journalisation, planification, self-service, séparation développement / exploitation.
- **Panorama 2026** :
  - **Semaphore UI 2.19** (MIT) : projets, inventaires, Key Store chiffré, templates de tâches, schedules, **Workflows** multi-templates (2.19), exécuteurs Docker / Kubernetes, intégrations webhook Git (HMAC), notifications, LDAP / OIDC, support Terraform / OpenTofu / PowerShell ; **édition Pro (~490 $/an)** et Enterprise.
  - **AWX 24.6.1 / AWX Operator 2.19.1** : aucune release depuis juillet 2024, refactoring « pluggable » en cours, déploiement Kubernetes uniquement, CVE non corrigées sur l'image ; **à ne plus installer en production en 2026**, mais utile pour comprendre le modèle Tower / AAP. Fork commercial Ascender.
  - **Red Hat Ansible Automation Platform 2.7** (GA juin 2026) : Platform Gateway, Automation Controller, Automation Hub privé, EDA Controller, Automation Portal self-service, Lightspeed intelligent assistant, installation conteneurisée ou OpenShift uniquement, licence par nœud géré, essai 60 jours.
  - Autres options vivantes : Rundeck 6.x (Apache 2.0, plugin Ansible 5.1) et PagerDuty Process Automation, Foreman + foreman_ansible, Uyuni / SUSE Multi-Linux Manager, Jenkins Ansible plugin, Kestra, Windmill, Ansible Forms (attention aux CVE 2026). Polemarch dormant.
- Grille de choix : équipe, taille du parc, besoins RBAC / audit / SSO, budget, compétence Kubernetes.
- Démo formateur : AWX sur k3s (job template, credentials, inventaire synchronisé depuis Git, webhook).
- **TP 11 — Semaphore UI (35 min)** : installation par paquet sur `tools`, connexion au dépôt Git fil rouge, Key Store (clé SSH, mot de passe vault), inventaire, template de tâche exécutant le playbook de patching, schedule, webhook déclenché par un push Git.

### Synthèse J2 (17h00–17h15)
- Récapitulatif, questions, tag `j2` sur le dépôt.

---

## 7. Jour 3 — Provisioning, réseau, Kubernetes, évolutions 2026 et clôture

> Journée mixte. Le TP Kubernetes (k3s) et le TP réseau (routeur VyOS) sont **réalisables dans le lab** et ont été validés contre les machines réelles. La partie **Proxmox / VMware reste théorique** : aucun hyperviseur n'est fourni, et il n'y a pas de démonstration sur infrastructure réelle — l'exercice se limite à l'écriture et à la validation statique du code.

### Module 3.1 — Provisioning d'infrastructure avec Ansible (9h00–10h45, 105 min)

**3.1.a Principes et positionnement (20 min)**
- Provisioning vs configuration : cycle de vie, état (state), plan / apply, destruction.
- **Terraform 1.16 / OpenTofu 1.12** vs Ansible : « Terraform provisionne, Ansible configure » ; quand Ansible seul suffit (on-prem Proxmox / VMware, pas de state à gérer), quand il ne suffit plus (drift, dépendances complexes, cloud multi-services).
- Intégration : collection `cloud.terraform` 4.x (module `terraform`, `terraform_output`, inventaires `terraform_state` et `terraform_provider`, `binary_path` pour OpenTofu), Packer + provisioner Ansible pour les images, Vagrant provisioner (déjà vu J1).
- Pattern cible : Packer (image) → Terraform/OpenTofu ou Ansible (VM) → inventaire dynamique → Ansible (configuration) → WebUI / CI.

**3.1.b Proxmox VE (45 min, théorie + démo)**
- Proxmox VE 9.2 (Debian 13, noyau 7.0) : API REST, utilisateurs et **tokens API**, rôles et privilèges minimaux pour l'automatisation.
- Collection **`community.proxmox` 2.0** (scission de `community.general` en 2025, redirections dépréciées) : `proxmox_kvm` (création, clonage de template, cloud-init : `ciuser`, `sshkeys`, `ipconfig`, `cicustom`), `proxmox` (LXC), `proxmox_vm_info`, `proxmox_template`, `proxmox_disk`, `proxmox_nic`, `proxmox_snap`, `proxmox_backup`, SDN, firewall, HA. Pré-requis `proxmoxer ≥ 2.3`, `validate_certs: true` par défaut.
- Inventaire dynamique `community.proxmox.proxmox` : `keyed_groups` par tags / pool / nœud, `want_facts`, filtres ; plugins de connexion `proxmox_pct_remote` et `proxmox_qemu_api`.
- Chaîne complète : template cloud-init Debian 13 → clone → personnalisation → attente SSH → inventaire dynamique → playbook de configuration.
- **Pas de démo sur infrastructure réelle** (aucun Proxmox fourni). **Exercice hors ligne** : écrire le playbook de création d'une VM et son `inventory.proxmox.yml`, validé par `ansible-lint` et `--syntax-check`. Commenter des captures d'écran de l'interface Proxmox si l'on veut illustrer.

**3.1.c VMware vSphere (30 min, théorie)**
- vSphere 9.1 (Broadcom, VCF 9) et paysage des collections : **`vmware.vmware` 2.10** (certifiée, socle actuel : `vm`, `deploy_folder_template`, `deploy_content_library_template`, `vm_apply_customization`, `vm_snapshot`, inventaires `vms` / `esxi_hosts`), **`community.vmware` 6.x** (dépend de `vmware.vmware`, SDK `vcf-sdk` remplace pyvmomi, `vmware_guest` encore la voie la plus complète pour clone + customisation, `vmware_vm_inventory` **déprécié** → migrer vers `vmware.vmware.vms`), `vmware.vmware_rest` (REST, en retrait).
- Authentification et comptes de service, tags vSphere comme source de groupes, Content Library, personnalisation invité (guest customization) vs cloud-init.
- Stratégie de migration des playbooks existants vers les FQCN `vmware.vmware.*`.

**3.1.d Cloud et autres cibles (10 min, survol)**
- `amazon.aws` 11.x, `azure.azcollection` 3.x, `google.cloud` 1.x : inventaires dynamiques, credentials via OIDC.
- `community.libvirt` (KVM local), `community.docker`, `containers.podman`.

*Pause 10h45–11h00*

### Module 3.2 — Automatisation réseau : switchs et routeurs (11h00–12h30, 90 min, théorie + démo)
- Spécificités du réseau : pas de Python sur l'équipement, exécution sur le contrôleur, connexions persistantes, `ansible_network_os`, `become` en mode `enable`.
- Collection **`ansible.netcommon` 8.x** : plugins de connexion `network_cli` (SSH + cliconf / terminal), `netconf`, `httpapi`, `grpc`, `libssh` ; modules génériques `cli_command`, `cli_config`, `cli_backup` / `cli_restore`, `netconf_get` / `netconf_config`, `restconf_*`, `network_resource`.
- **Resource modules** et leurs états : `merged`, `replaced`, `overridden`, `deleted`, `gathered`, `rendered`, `parsed` ; approche « configuration en tant que données » ; `gathered` + `rendered` pour migrer une configuration existante vers Ansible ; `parsed` / `rendered` fonctionnent **hors ligne** (base des exercices).
- `ansible.utils` : `cli_parse` (TextFSM / ntc-templates, TTP, pyATS), `validate` (JSON Schema), `fact_diff`, filtres `ipaddr`.
- **Collections vendeurs, état 2026** : maintenues et dans Ansible 14 — `cisco.ios` 11.x (40 resource modules : `ios_interfaces`, `ios_vlans`, `ios_l2_interfaces`, `ios_l3_interfaces`, `ios_acls`, `ios_ospfv2`, `ios_bgp_*`, `ios_vrf_*`), `cisco.nxos`, `cisco.iosxr`, `arista.eos` 12.x (CLI + eAPI), `vyos.vyos` 6.x, `fortinet.fortios`, `community.routeros` (MikroTik, API), `dellemc.enterprise_sonic` ; hors paquet — `paloaltonetworks.panos`, `arubanetworks.aoscx` ; **Juniper : `junipernetworks.junos` archivée en mars 2026 → `juniper.device`** ; à éviter — `dellemc.os10`, `arubanetworks.aos_switch`, `community.network` (retirée).
- Source de vérité et inventaire : **NetBox** (`netbox.netbox` 3.23 : `nb_inventory`, `nb_lookup`, modules de mise à jour) ou **Nautobot** (`networktocode.nautobot` 6.x) ; boucle NetBox → Ansible → équipement → `gathered` → NetBox (détection de drift).
- Sécurité et exploitation : sauvegarde avant changement (`cli_backup`), `--check` / `--diff` sur équipements, fenêtres de maintenance, `serial: 1`, rollback (`cli_restore`, `commit confirmed` NETCONF), gestion des credentials réseau.
- **Labs gratuits pour continuer après la formation** : Containerlab 0.79 (Nokia SR Linux gratuit, Arista cEOS-lab sur inscription, FRR, VyOS), Cisco CML-Free (5 nœuds IOL / ASAv), GNS3 3.x ; EVE-NG Community en fin de vie.
- **Démo formateur** : Containerlab (SR Linux + FRR) ou VyOS Vagrant (`net1`) — `network_cli`, `gathered` sur les interfaces, `merged` d'un VLAN, `cli_backup`, `--diff`.
- **Exercice hors ligne (25 min)** : à partir d'un `show running-config` Cisco IOS fourni, produire le modèle de données (`parsed`), le modifier, régénérer la configuration (`rendered`), valider avec `ansible.utils.validate` ; écrire un `nb_inventory` type.

*Déjeuner 12h30–13h30*

### Module 3.3 — Ansible et Kubernetes (13h30–15h15, 105 min)
- Où Ansible reste pertinent dans un monde GitOps : **bootstrap** du cluster, **day-2 des nœuds** (OS, noyau, `k8s_drain`, upgrades), dépendances **hors cluster** (DNS, load balancer, stockage, PKI, registry), installation initiale d'ArgoCD / Flux via `helm` ; ce qu'il ne faut plus faire avec Ansible (déploiement applicatif continu → ArgoCD / Flux).
- Construire un cluster : **Kubespray 2.31** (Kubernetes 1.35, kubeadm sous le capot, HA), **k3s-ansible 1.2** (collection officielle k3s-io, HA etcd, airgap), rôle `lablabs.rke2`, kubeadm « maison ». Critères de choix.
- Collection **`kubernetes.core` 6.6** : `k8s` (manifests inline / fichiers / templates Jinja2, `apply`, `server_side_apply`, `wait`), `k8s_info`, `k8s_scale`, `k8s_exec`, `k8s_log`, `k8s_json_patch`, `k8s_drain`, `kubeconfig`, lookups `k8s` et `kustomize` ; modules **Helm** (`helm`, `helm_repository`, `helm_pull`, `helm_template`, compatibilité Helm 4) ; pré-requis client Python `kubernetes`, authentification (kubeconfig, token, OIDC).
- Ansible **dans** Kubernetes : execution environments comme images de jobs / CronJobs, `ansible-runner`, exécuteur Kubernetes de Semaphore, AWX Operator (état gelé), Ansible Operator SDK (`ansible-operator-plugins` 1.42, déprécié côté OpenShift pour les nouveaux projets).
- Sécurité : RBAC Kubernetes pour le compte d'automatisation, secrets (Sealed Secrets / External Secrets vs vault Ansible), `no_log`.
- **TP 14 — Cluster k3s et déploiement applicatif (50 min)** : monter un cluster k3s (1 plan de contrôle + 2 workers Debian 13) avec la collection `k3s.orchestration`, en forçant `node-ip` et `flannel-iface` sur l'interface host-only ; récupérer le kubeconfig sur le contrôleur ; déployer avec `kubernetes.core` un namespace et une application (Deployment + Service + Ingress) templatisée en Jinja2, puis un chart via `helm` ; drainer et réintégrer un worker ; vérifier l'idempotence.

*Pause 15h15–15h30*

### Module 3.4 — Évolutions 2026 : Event-Driven Ansible, IA, Windows (15h30–16h15, 45 min)
- **Event-Driven Ansible** : `ansible-rulebook` 1.3 (Python 3.9–3.12, moteur Drools / JDK), sources d'événements (webhook, Kafka, Prometheus / Alertmanager, journal), règles, conditions, actions (`run_playbook`, `run_job_template`), cas d'usage de remédiation automatique, EDA Controller dans AAP 2.7. Démo formateur : webhook → rulebook → playbook de redémarrage de service.
- **IA et Ansible** : Red Hat « Automation coding assistant » (ex-Lightspeed, inclus dans AAP, BYO-LLM), Lightspeed intelligent assistant dans l'UI AAP, serveur MCP officiel `aap-mcp-server` et collection `ansible.mcp` ; alternatives gratuites — MCP intégré à l'extension VS Code, serveurs MCP communautaires, assistants génériques (Copilot, Claude Code, Cursor) **encadrés par ansible-lint profil `production` et molecule** ; bonnes pratiques et risques (hallucination de modules, FQCN inventés, secrets dans les prompts).
- **Windows** en bref : `psrp` à préférer à `winrm`, **SSH natif officiellement supporté depuis core 2.18** (OpenSSH ≥ 7.9, Windows Server 2022+), collection `ansible.windows` 3.x, cas Kerberos / double-hop.
- Ce qui a changé récemment et à surveiller : moteur de templating 2.19+, exclusion automatique des collections incompatibles (2.21), versionnement calendaire de l'outillage, AAP conteneurisé uniquement, fin de HCP Vagrant Registry.

### Module 3.5 — Synthèse, feuille de route et clôture (16h15–17h00, 45 min)
- Revue du fil rouge : de l'inventaire J1 au déploiement Kubernetes J3, ce qu'un projet Ansible « niveau production » contient (checklist remise aux stagiaires).
- Feuille de route d'adoption en entreprise : inventaire de l'existant, quick wins, gouvernance du dépôt, CI obligatoire, WebUI, secrets, montée en compétence, indicateurs.
- Ressources pour continuer : documentation officielle, forum Ansible, Red Hat CoP good practices, dépôts d'exemples, labs réseau gratuits, communauté francophone.
- Certification : Red Hat EX294 (RHCE) et son périmètre ; positionnement des contenus de la formation.
- Quiz final (20 min), fiche d'auto-positionnement, évaluation de la formation.

---

## 8. Récapitulatif des travaux pratiques

| # | Jour | Intitulé | Durée | Cibles |
|---|---|---|---|---|
| 01 | J1 | Mise en place du lab et premier `ping` | 30 min | toutes |
| 02 | J1 | Inventaire du fil rouge et audit ad hoc | 25 min | toutes |
| 03 | J1 | Premier playbook multi-OS (configuration de base) | 35 min | `web*`, `db01` |
| 04 | J1 | Déploiement nginx templatisé, handlers, idempotence | 40 min | `web01`, `web02` |
| 05 | J1 | Rôle base de données via collection / rôle Galaxy | 35 min | `db01` |
| 06 | J2 | Mise à jour orchestrée du parc (`serial`, `reboot`, `rescue`) | 35 min | toutes |
| 07 | J2 | Inventaire construit et cache de facts | 20 min | toutes |
| 08 | J2 | ansible-lint profil `production` + Molecule multi-OS | 35 min | conteneurs |
| 09 | J2 | Pipeline CI + execution environment | 40 min | `tools`, CI |
| 10 | J2 | Secrets : ansible-vault multi-id puis SOPS/age | 20 min | `db01` |
| 11 | J2 | Semaphore UI : installation, template, schedule, webhook | 35 min | `tools` |
| 12 | J3 | Provisioning Proxmox hors ligne (playbook + inventaire dynamique) | 20 min | aucune |
| 13 | J3 | Réseau hors ligne (`parsed` → `rendered` → `validate`) | 25 min | aucune |
| 14 | J3 | Cluster k3s, `kubernetes.core`, Helm, drain de nœud | 50 min | `k3s-*` |

Total TP et exercices : environ 7 h 25, soit 35 % du temps, complété par environ 1 h 30 de démonstrations formateur (AWX, Proxmox, vSphere, Containerlab / VyOS, EDA).

---

## 9. Versions de référence (septembre 2026)

| Composant | Version | Remarque |
|---|---|---|
| ansible-core | 2.21.4 | Python contrôleur 3.12–3.14, cibles 3.9–3.14 ; EOL nov. 2027 |
| Ansible (paquet communautaire) | 14.4.0 | Ansible 13 EOL juin 2026 |
| ansible-dev-tools / ansible-lint / molecule / navigator / creator | 26.8.x | Versionnement calendaire |
| ansible-builder / ansible-runner | 3.1.1 / 2.4.3 | Format EE v3 |
| Extension VS Code redhat.ansible | 26.8.2 | LSP, MCP intégré |
| Semaphore UI | 2.19.12 | MIT ; Pro ~490 $/an |
| AWX / AWX Operator | 24.6.1 / 2.19.1 | Gelé depuis juillet 2024 |
| Red Hat AAP | 2.7 | GA juin 2026, conteneurisé uniquement, essai 60 jours |
| Rundeck | 6.2.1 | Plugin Ansible 5.1.3 |
| community.proxmox | 2.0.x | Proxmox VE 9.2 ; proxmoxer ≥ 2.3 |
| vmware.vmware / community.vmware / vmware.vmware_rest | 2.10 / 6.x / 4.11 | vSphere 9.1 ; `vmware_vm_inventory` déprécié |
| cloud.terraform | 4.0 | Terraform 1.16, OpenTofu 1.12 |
| ansible.netcommon / ansible.utils | 8.6 / 6.1 | |
| cisco.ios / arista.eos / vyos.vyos / juniper.device | 11.5 / 12.2 / 6.0 / — | `junipernetworks.junos` archivée mars 2026 |
| netbox.netbox / networktocode.nautobot | 3.23 / 6.3 | |
| kubernetes.core | 6.6.0 | Helm 4 supporté |
| Kubespray / k3s-ansible | 2.31 (k8s 1.35) / 1.2.2 | |
| ansible-rulebook (EDA) | 1.3.1 | Python 3.9–3.12, JDK requis |
| ansible.windows | 3.8.0 | SSH natif depuis core 2.18 |
| Vagrant / VirtualBox | 2.4.9 / 7.2.18 | HCP Vagrant Registry décommissionné le 31 déc. 2026 |
| Boxes | bento/debian-13, bento/rockylinux-10 | À pré-télécharger |
| Containerlab / CML-Free / GNS3 | 0.79 / 2.10 / 3.0.6 | Labs réseau gratuits |

---

## 10. Livrables de la formation

- Support de cours (slides) par module.
- Dépôt Git `formation-ansible` : `Vagrantfile`, squelette de projet, énoncés et corrigés des 12 TP et des 2 exercices hors ligne (sur branches dédiées).
- Fiches mémo : CLI Ansible, structure de projet et nommage, profils ansible-lint, états des resource modules, matrice « quel outil pour quoi » (Ansible / Terraform / Helm / ArgoCD).
- Checklist « projet Ansible niveau production ».
- Kit de préparation du poste stagiaire et du kit formateur (section 3.3), incluant le dépôt de boxes local.
