# Audit technique de la formation Ansible

Audit du 22 septembre 2026, organisé par TP. Périmètre : énoncés, corrigés, configuration commune, dépendances et continuité du fil rouge.

**Verdict : les corrigés passent les contrôles statiques, mais plusieurs erreurs empêchent de terminer le parcours tel qu'il est livré.** Les premières corrections à faire concernent les paquets Rocky, le template nginx du TP 04, l'ordre de création PostgreSQL, les tests Molecule et le déploiement Kubernetes.

## Méthode et limites

- Environnement local : `ansible-core 2.21.4`, Python 3.14.7, installation Homebrew. Ce n'est pas le poste Ubuntu/pipx prévu pour les stagiaires.
- Consultation en ligne des documentations officielles Ansible, PostgreSQL, nginx, K3s, Vagrant, Python Packaging et des dépôts Rocky/Fedora. Les liens figurent auprès des constats ; les pages `latest` peuvent évoluer.
- Contrôle `--syntax-check` réussi pour les **14 playbooks principaux** : TP 03, 04, 05, 06, 10, 11, les deux playbooks de provisioning, les trois playbooks réseau et les trois playbooks Kubernetes.
- `ansible-lint --offline --profile production corrige/` : premier passage en échec sur sept modules introuvables dans l'environnement du lint ; second passage réussi, **87 fichiers analysés, zéro violation**, après ajout explicite du répertoire des collections Homebrew à `ANSIBLE_COLLECTIONS_PATH`. Ce premier échec est un écart d'environnement local, pas la preuve d'un module inexistant.
- `molecule list` accepte le scénario ; cela valide sa configuration, pas son exécution.
- Lecture locale des inventaires ; exécution réussie de la démonstration Vault du TP 10 et du parsing de fichier du TP 13, sans connexion distante ni modification système.
- **Aucune VM, aucun VirtualBox, aucun conteneur et aucun cluster démarrés. Aucun playbook de provisioning ou de configuration distante exécuté, même en `--check`.** Les comportements dépendant d'une box sont explicitement signalés comme restant à vérifier.

Gravité : **P1** = bloque une étape normale du TP ; **P2** = résultat incorrect, validation trompeuse ou panne conditionnelle. « Confirmé » signifie établi par lecture du code et documentation, ou reproduit localement ; cela ne signifie pas testé sur VM.

## TP 01 — Mise en place du lab

### 01.1 — P2 — La commande générique d'utilisation des corrigés pointe vers un inventaire absent

**Fichier :** [corrige/README.md](corrige/README.md), section « Utilisation ».

L'exemple utilise `corrige/tp03-playbook-base/inventories/dev/hosts.yml`, qui n'existe pas. Le TP 03 réutilise l'inventaire du TP 02. Ansible peut alors terminer sans appliquer le play à aucune cible, ce qui est trompeur pour un premier essai.

**Correction :** remplacer le chemin par `corrige/tp02-inventaire/inventories/dev/hosts.yml`, comme le fait déjà le README propre au TP 03. **Confirmé par l'arborescence.**

### 01.2 — P2 — Le poste de contrôle annoncé n'est pas reproductible

**Fichiers :** [module 02](J1-Socle/02-Noeud-De-Controle.md), §1.3 ; [collections/requirements.yml](collections/requirements.yml) ; [PLAN.md](PLAN.md).

`pipx install --include-deps ansible`, `pipx install ansible-lint` et `pipx install molecule` ne fixent aucune version. Toutes les collections utilisent des minima `>=`, alors que le commentaire indique qu'elles sont épinglées. La procédure peut donc installer un autre moteur et d'autres collections que ceux du support. Le plan prescrit également `ansible-dev-tools`, contrairement au parcours effectif fondé sur trois installations séparées.

**Correction :** fixer une matrice effectivement validée, l'appliquer aux commandes et aux requirements, et aligner le plan. La résolution des dépendances n'est pas un verrouillage de versions. Voir la [documentation Galaxy sur les versions des collections](https://docs.ansible.com/projects/ansible/latest/shared_snippets/installing_collections_file.html).

**Limite :** la disponibilité et le démarrage des boxes, la compilation de VirtualBox et les accès SSH du lab ne sont pas validés par cet audit.

## TP 02 — Inventaire du fil rouge

### 02.1 — P1 — La liste de paquets Rocky n'est pas adaptée aux dépôts ordinaires

**Fichiers :** [group_vars/rocky.yml](corrige/tp02-inventaire/inventories/dev/group_vars/rocky.yml), lignes 5–6 ; même liste dans le [TP 07](corrige/tp07-inventaire-dynamique/inventories/dev/group_vars/rocky.yml).

La liste contient `htop` et `python3-libdnf5`. Aucun rôle ni bootstrap n'active EPEL. `htop` est distribué dans EPEL ; le dépôt Rocky 10 consulté expose `python3-dnf` et `python3-libdnf`, tandis que `python3-libdnf5` n'apparaît pas dans les listes BaseOS/AppStream consultées. Présenter EL10 comme systématiquement passé à DNF5 est incorrect : DNF4 est encore distribué.

**Impact :** installation des paquets de base susceptible d'échouer sur `db01` au TP 03, puis dans le rôle `base` au TP 05. Une box qui aurait déjà des dépôts additionnels peut masquer une partie du problème ; son état n'a pas été inspecté.

**Correction :** utiliser les dépendances du gestionnaire réellement présent, typiquement `python3-dnf`, et activer explicitement EPEL pour `htop` ou retirer ce paquet du socle. Sources : [BaseOS Rocky 10](https://dl.rockylinux.org/pub/rocky/10/BaseOS/x86_64/os/Packages/p/), [AppStream Rocky 10](https://dl.rockylinux.org/pub/rocky/10/AppStream/x86_64/os/Packages/p/), [htop dans Fedora/EPEL](https://packages.fedoraproject.org/pkgs/htop/htop/).

L'inventaire lui-même se charge ; aucun blocage de structure ou de précédence n'a été identifié dans le corrigé TP 02.

## TP 03 — Premier playbook multi-OS

### 03.1 — P1 — Le premier `--check` ne peut pas valider une machine vierge comme annoncé

**Fichiers :** [base.yml](corrige/tp03-playbook-base/playbooks/base.yml), tâches d'installation, de service et de clé autorisée ; [module 04](J1-Socle/04-Playbooks.md), déroulé attendu.

Le déroulé demande une simulation avant la première application. En simulation, les paquets et le compte `ansible` ne sont pas créés. Les tâches suivantes peuvent donc chercher un service absent ou tenter `authorized_key` pour un utilisateur inexistant. La présence d'une clé publique, explicitement préparée dans le README, rend ce second cas concret. Le même problème se propage aux premiers passages nginx et PostgreSQL des TP suivants.

**Correction :** distinguer simulation sur machine déjà convergée et premier bootstrap. Adapter les tâches dépendantes à `ansible_check_mode` avec un état préalable vérifié, ou documenter un premier passage réel avant la validation de dérive. Ne pas promettre qu'une simulation installe les prérequis des tâches suivantes. Source : [limites du check mode](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_checkmode.html).

Le défaut de paquets du TP 02 s'applique également ici. Aucun échec distant n'a été provoqué pour le vérifier.

## TP 04 — Serveurs web pilotés par les données

### 04.1 — P1 — Mauvaise variable de boucle dans le dépôt de la page HTML

**Fichier :** [web.yml](corrige/tp04-nginx/playbooks/web.yml), tâche `Deposer la page d accueil de chaque site`.

La tâche déclare `loop_var: site`, mais `dest` utilise encore `{{ item.nom }}`. `item` n'est pas défini dans cette boucle : l'exécution échoue avant de déposer les pages. Le fait que la tâche précédente utilise `item` ne le rend pas disponible dans la suivante.

**Correction :** `dest: "{{ site_racine }}/{{ site.nom }}/index.html"`. Le rôle nginx du TP 05 utilise déjà la bonne écriture. **Confirmé par lecture.**

### 04.2 — P1 — Les contrôles HTTP suivent une redirection vers un HTTPS inexistant

**Fichiers :** [web.yml](corrige/tp04-nginx/playbooks/web.yml), ligne 125 ; [vhost.conf.j2](corrige/tp04-nginx/playbooks/templates/vhost.conf.j2) ; même contrôle dans le [rôle nginx](corrige/tp05-roles/roles/nginx/tasks/main.yml).

Les requêtes vont à `127.0.0.1` sans en-tête `Host` correspondant au site. Elles interrogent donc le serveur par défaut du port, pas nécessairement le vhost attendu. Sur Debian, avec les fichiers inclus dans l'ordre habituel, `ancien.conf` précède `vitrine.conf` pour le port 80 et renvoie un 301 vers HTTPS. Le module `uri` suit par défaut les redirections GET ; autoriser `status_code: [200, 301]` ne désactive pas ce suivi. Aucun serveur TLS n'est installé : le contrôle échoue.

**Correction :** fournir `headers: {Host: "{{ site.nom }}.{{ parc_domaine }}"}`, `follow_redirects: none` et attendre 301 uniquement pour `ancien`, 200 pour les autres. Corriger aussi les `curl` sans `Host` et le contrôle du TP 06. Sources : [sélection du serveur nginx](https://nginx.org/en/docs/http/request_processing.html), [options de `uri`](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/uri_module.html).

### 04.3 — P2 — La vérification du reverse proxy n'a aucun backend

**Fichiers :** [module 05](J1-Socle/05-Variables-Jinja-Handlers.md), section « Vérification » ; [web.yml](corrige/tp04-nginx/playbooks/web.yml), dictionnaire `proxies`.

Le `curl` vers `/v1/` vise indirectement `127.0.0.1:9001`. Aucun service n'est déployé sur 9001 ou 9002 dans le parcours. Sur un lab neuf, cette vérification obtient un 502, même après correction des vhosts.

**Correction :** fournir un backend minimal, ou annoncer explicitement le 502 attendu et tester séparément la page statique et le rendu de configuration. **Confirmé par l'absence de déploiement des backends dans le dépôt.**

## TP 05 — Du playbook aux rôles

### 05.1 — P1 — La base est créée avant son propriétaire

**Fichiers :** [roles/postgres/tasks/main.yml](corrige/tp05-roles/roles/postgres/tasks/main.yml), lignes 26 et 39 ; [site.yml](corrige/tp05-roles/site.yml).

`postgres_bases` demande `proprietaire: applicatif`. Le rôle tente de créer la base avant de créer ce rôle PostgreSQL. Sur un cluster initialisé par le TP, `applicatif` n'existe pas : la création échoue avec un rôle propriétaire inexistant.

**Correction :** comptes d'abord, bases ensuite, privilèges enfin. La tâche de création des comptes ne dépend actuellement pas de la base applicative. Sources : [CREATE DATABASE et OWNER](https://www.postgresql.org/docs/current/sql-createdatabase.html), [module postgresql_db](https://docs.ansible.com/projects/ansible/latest/collections/community/postgresql/postgresql_db_module.html).

### 05.2 — P2 — Le port PostgreSQL est paramétrable en apparence seulement

**Fichiers :** [rôle postgres](corrige/tp05-roles/roles/postgres/tasks/main.yml), [defaults](corrige/tp05-roles/roles/postgres/defaults/main.yml).

`postgres_port` configure uniquement firewalld. Le rôle ne configure ni le port d'écoute PostgreSQL, ni `listen_addresses`, ni `pg_hba.conf`. Changer cette variable ouvre un autre port sans déplacer le serveur ; ouvrir le pare-feu ne rend pas, à lui seul, le compte applicatif utilisable à distance.

**Correction :** soit annoncer un TP de base locale et retirer cette promesse de configuration réseau, soit gérer les paramètres serveur et l'authentification, puis tester la connexion applicative. Ce point ne bloque pas les opérations SQL locales du corrigé.

Les défauts 02.1, 03.1 et 04.2 restent applicables au playbook `site.yml`.

## TP 06 — Mise à jour orchestrée du parc

### 06.1 — P1 — Les commandes de vérification omettent les variables du TP

**Fichier :** [README du TP 06](corrige/tp06-patching/README.md), section « Vérification ».

La section « Contenu » passe deux sources `-i`, mais la section « Vérification » n'utilise que l'inventaire TP 02. `maj_commande_reboot` et `maj_rc_reboot_requis` ne sont alors pas chargées. Le playbook échoue à la détection du reboot.

**Correction :** utiliser les deux sources dans toutes les commandes, ou fusionner les variables dans l'inventaire du projet. **Vérifié localement :** avec les deux sources, `--host db01` expose les variables ; sans la seconde, elles sont absentes. Le répertoire ne contenant que `group_vars` génère un avertissement de parsing mais ses variables sont bien chargées sur la version locale : ce n'est pas un blocage supplémentaire.

### 06.2 — P2 — Le fichier `MAINTENANCE` ne retire pas le serveur de la rotation

**Fichiers :** [patching.yml](corrige/tp06-patching/playbooks/patching.yml), tâche `Sortir la machine de la rotation` ; templates nginx TP 04/05.

Le play écrit `/var/www/formation/MAINTENANCE`, mais aucune configuration nginx ni aucun répartiteur ne consulte ce fichier. Les requêtes continuent à arriver. La garantie d'une sortie de rotation avant intervention n'est donc pas implémentée.

**Correction :** relier réellement cet état à un répartiteur/healthcheck, ou présenter le fichier comme une simulation pédagogique sans effet sur le trafic. **Confirmé par lecture croisée.**

### 06.3 — P2 — Une erreur de détection du reboot est transformée en décision métier

**Fichiers :** [patching.yml](corrige/tp06-patching/playbooks/patching.yml), lignes 48–56 ; [variables Rocky](corrige/tp06-patching/inventories/dev/group_vars/rocky.yml) ; README.

`failed_when: false` absorbe toutes les erreurs, puis le code retour est comparé à une unique valeur. Un plugin `needs-restarting` absent peut ainsi être interprété comme « reboot nécessaire » si l'erreur vaut 1, ou « pas de reboot » pour un autre code. Le support justifie l'absence d'installation du plugin par une intégration supposée à DNF5 ; ce n'est pas une propriété générale de Rocky 10.

**Correction :** installer/vérifier le fournisseur de la commande et ne tolérer que les retours documentés, en conservant une erreur explicite pour les autres. Sources : [DNF needs-restarting](https://dnf-plugins-core.readthedocs.io/en/latest/needs_restarting.html), [paquets DNF Rocky 10](https://dl.rockylinux.org/pub/rocky/10/BaseOS/x86_64/os/Packages/d/).

Le contrôle HTTP hérite aussi du défaut 04.2. La présence systématique de `/var/run/reboot-required` sur cette box Debian n'a pas été établie : le bootstrap ne garantit aucun producteur de ce fichier. Ne pas présenter son absence comme une preuve universelle qu'aucun reboot n'est nécessaire.

## TP 07 — Inventaire construit et cache de facts

### 07.1 — P2 — La variable `fqdn` demandée par l'énoncé n'est jamais composée

**Fichier :** [02-constructed.yml](corrige/tp07-inventaire-dynamique/inventories/dev/02-constructed.yml), ligne 14.

`fqdn` dépend de `parc_domaine`, qui est placé dans `group_vars/all.yml`. Le plugin n'active pas `use_vars_plugins`. Avec `strict: false`, l'échec de composition est silencieusement ignoré. **Reproduit :** `ansible-inventory -i corrige/tp07-inventaire-dynamique/inventories/dev/ --host web01` contient `parc_domaine` une fois le chargement terminé, mais aucun `fqdn`.

**Correction :** porter aussi `parc_domaine` dans `01-hosts.yml`, ou activer volontairement `use_vars_plugins: true`. Nuancer l'affirmation du support selon laquelle les `group_vars` seraient toujours invisibles : c'est le comportement par défaut, pas une impossibilité. Source : [constructed et use_vars_plugins](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/constructed_inventory.html).

### 07.2 — P1 — La reprise du patching avec le corrigé TP 07 perd ses prérequis

**Fichiers :** [README TP 07](corrige/tp07-inventaire-dynamique/README.md), section « Utilisation avec le TP 06 » ; inventaire fourni.

Les nouvelles variables du TP 06 ne sont pas présentes dans l'inventaire TP 07. Les commandes de reprise n'indiquent ni cet inventaire, ni la surcharge du TP 06. Sur les corrigés livrés, le ciblage canari ou la détection du reboot échoue selon la configuration active.

**Correction :** fournir une commande complète utilisant le répertoire TP 07 et les variables de patching, ou livrer un inventaire cumulatif. Cette réserve concerne l'utilisation des corrigés ; un stagiaire ayant conservé ses variables dans son projet peut éviter le problème.

## TP 08 — Qualité : ansible-lint et Molecule

### 08.1 — P1 — `verify.yml` utilise des variables de rôle qu'il ne charge pas

**Fichier :** [verify.yml](corrige/tp05-roles/roles/nginx/molecule/default/verify.yml), lignes 24 et 43.

Le play de vérification utilise `nginx_chemins`, défini uniquement dans `roles/nginx/vars/main.yml`. Il n'importe ni le rôle ni ce fichier. `converge` et `verify` sont deux exécutions distinctes : les variables du rôle ne persistent pas entre elles. L'inspection des vhosts échoue sur une variable indéfinie.

**Correction :** charger explicitement les données requises avec `vars_files`/`include_vars`, ou définir des attentes de test indépendantes du rôle. La portée des variables ne permet pas de réutiliser implicitement celles du play précédent. Source : [portée des variables Ansible](https://docs.ansible.com/projects/ansible/latest/reference_appendices/general_precedence.html).

### 08.2 — P1 — Le test HTTP ne vise pas `vitrine` et ne possède pas le domaine du scénario

**Fichiers :** [converge.yml](corrige/tp05-roles/roles/nginx/molecule/default/converge.yml) et [verify.yml](corrige/tp05-roles/roles/nginx/molecule/default/verify.yml), ligne 53.

`converge` crée des sites sous `test.local`, mais `verify` appelle seulement `http://127.0.0.1/`. Même après réparation de la variable manquante, le test peut tomber sur `ancien` et suivre son HTTPS inexistant. Le rôle échoue déjà pendant `converge` avec le contrôle décrit en 04.2.

**Correction :** réparer les contrôles du rôle, puis vérifier `vitrine.test.local` avec un en-tête `Host` et un statut 200 explicites. Le simple succès de `molecule list` ne couvre aucun de ces problèmes.

**À vérifier ultérieurement sur Rocky :** `nginx_chemins.RedHat.site_defaut` suppose `/etc/nginx/conf.d/default.conf`. Si le serveur par défaut du paquet est défini directement dans `nginx.conf`, cette suppression ne le désactive pas. L'emplacement exact dans l'image utilisée n'a pas été contrôlé ici ; ce point reste une réserve, pas un échec reproduit.

## TP 09 — Chaîne d'intégration du projet

### 09.1 — P1 — L'execution environment casse lorsqu'on suit la consigne de copie

**Fichiers :** [execution-environment.yml](corrige/tp09-cicd/execution-environment.yml), ligne 30 ; [README](corrige/tp09-cicd/README.md).

Le README demande de placer les fichiers à la racine du projet. Or `galaxy: ../../collections/requirements.yml` est écrit pour l'emplacement dans `corrige/tp09-cicd/`. Après copie à la racine, il pointe hors du projet et le fichier requis n'existe plus à cet emplacement.

**Correction :** pour la version à copier, utiliser `galaxy: collections/requirements.yml`. Distinguer clairement cette procédure d'une construction utilisant directement le fichier du corrigé. Sources : [définition d'un EE](https://docs.ansible.com/projects/builder/en/latest/definition/), [CLI Builder](https://docs.ansible.com/projects/builder/en/latest/usage/).

### 09.2 — P1 — Le workflow GitHub lance Molecule sur un rôle sans scénario

**Fichier :** [workflow d'exemple](corrige/tp09-cicd/.github/workflows/ansible.yml), matrice `role: [nginx, base]`.

Seul `nginx` possède `molecule/default/`. Le job `base` ne dispose d'aucun scénario à lancer. Les défauts du TP 08 font également échouer le job nginx avant de pouvoir obtenir une CI verte.

**Correction :** réduire la matrice à nginx, ou fournir et documenter un scénario pour base. **Confirmé par l'arborescence.** Le workflow actif à la racine du dépôt ne lance que le lint et ne détecte donc pas ces défauts.

### 09.3 — P1 — La CI de déploiement ne possède ni les clés Vagrant ni une route garantie vers le lab

**Fichiers :** [.gitlab-ci.yml](corrige/tp09-cicd/.gitlab-ci.yml), jobs `check`/`deploy` ; inventaires du fil rouge ; [module 10](J2-Industrialisation/10-Git-CICD.md).

Les jobs provisionnent uniquement le mot de passe Vault. L'inventaire utilise des fichiers `.vagrant/machines/.../private_key`, exclus de Git et absents d'un checkout CI. Un runner hébergé n'a pas non plus accès au réseau host-only `192.168.56.0/24`. Enfin, aucun inventaire de production complet n'est livré pour la commande `inventories/prod/`.

**Correction :** documenter un runner accessible au lab, fournir une identité SSH dédiée par secret CI et un inventaire adapté ; réserver le job prod à un environnement effectivement décrit. Ne pas confondre l'exécution possible du lint avec celle du déploiement. Les variables de connexion de l'inventaire peuvent aussi primer sur une clé passée en option CLI : [règles de précédence](https://docs.ansible.com/projects/ansible/latest/reference_appendices/general_precedence.html).

### 09.4 — P1 — `ansible-builder` et `ansible-navigator` ne sont pas installés par le parcours principal

**Fichiers :** [module 02](J1-Socle/02-Noeud-De-Controle.md), §1.3 ; [README TP 09](corrige/tp09-cicd/README.md), vérification EE.

Le parcours installe Ansible, lint et Molecule séparément. Le TP 09 installe pre-commit, puis appelle Builder et Navigator sans ajouter leur installation. L'alternative `ansible-dev-tools` du module 02 n'est pas le chemin suivi par défaut.

**Correction :** ajouter leurs installations explicites et leurs versions avant les commandes EE. Sur le poste de cet audit, `ansible-builder` n'était pas disponible ; aucune construction n'a été tentée.

## TP 10 — Chiffrer les secrets du fil rouge

### 10.1 — P2 — Le corrigé démontre Vault sans appliquer le secret au fil rouge

**Fichiers :** [corrigé TP 10](corrige/tp10-secrets/README.md), [demo-secrets.yml](corrige/tp10-secrets/playbooks/demo-secrets.yml), [site.yml du TP 05](corrige/tp05-roles/site.yml).

L'énoncé demande de remplacer le mot de passe en clair dans `site.yml`. Le corrigé ne livre pas ce changement : le seul playbook fourni affiche la longueur du secret. Le playbook TP 05 conserve `mot_de_passe: motdepasse-a-chiffrer` ; lui ajouter l'inventaire Vault ne remplace pas cette valeur littérale.

**Correction :** fournir le playbook cumulatif ou le diff attendu, notamment `mot_de_passe: "{{ postgresql_motdepasse }}"`. Vérifier ensuite que le rôle consomme cette variable.

**Vérifié localement :** la démonstration dev déchiffre bien son fichier et affiche la longueur 27, sans connexion à `db01`. Il n'y a donc pas de bug de chiffrement établi ; le défaut porte sur l'intégration demandée par le TP.

## TP 11 — Déployer et exploiter Semaphore UI

### 11.1 — P1 — L'inventaire Vagrant n'est pas exécutable depuis Semaphore tel quel

**Fichiers :** [module 12](J2-Industrialisation/12-WebUI.md), partie interface ; [variables SSH du TP 02](corrige/tp02-inventaire/inventories/dev/group_vars/all.yml).

Le TP demande d'associer une clé du Key Store à l'inventaire existant. Mais celui-ci impose toujours une clé privée différente par VM sous `.vagrant/...`, présente sur le poste du stagiaire, pas dans le checkout de Semaphore. Il conserve aussi `ansible_user: vagrant` au lieu d'utiliser le compte `ansible` préparé au TP 03. Une clé du Key Store ne corrige pas automatiquement ces variables de connexion prioritaires.

**Correction :** fournir un inventaire d'exécution Semaphore qui utilise le compte `ansible`, autoriser la clé dédiée sur les cibles et supprimer la référence aux chemins privés Vagrant. Source : [précédence des variables de connexion](https://docs.ansible.com/projects/ansible/latest/reference_appendices/general_precedence.html).

### 11.2 — P2 — Semaphore exécute un autre Ansible que celui enseigné

**Fichier :** [roles/semaphore/tasks/main.yml](corrige/tp11-semaphore/roles/semaphore/tasks/main.yml), ligne 12.

Le rôle installe `ansible-core` depuis apt sur Debian, alors que le module 02 écarte précisément cette version pour utiliser core 2.21. Le parcours introduit donc un second contrôleur sans sa matrice de versions et de dépendances. L'installation automatique des collections par Semaphore ne met pas à niveau le moteur ni ses dépendances Python.

**Correction :** installer un environnement d'exécution explicite pour le compte Semaphore et vérifier le binaire réellement invoqué. Ce décalage est confirmé par la procédure, mais aucun échec dû à une collection particulière n'est affirmé ici. Source : [installation et dépendances Semaphore](https://semaphoreui.com/docs/admin-guide/installation).

### 11.3 — P2 — Les clés de chiffrement peuvent apparaître dans les différentiels

**Fichier :** [roles/semaphore/tasks/main.yml](corrige/tp11-semaphore/roles/semaphore/tasks/main.yml), tâche `Deposer la configuration`, ligne 87.

Les `set_fact` sont protégés par `no_log`, mais la tâche `template` qui écrit les mêmes clés ne désactive pas le diff. Le réflexe `--diff` enseigné dans le parcours affiche alors le contenu du fichier, avec les clés de chiffrement. Le template k3s expose de la même manière son token.

**Correction :** `diff: false` sur ces templates et `no_log` sur les lectures/traitements sensibles selon le niveau de verbosité autorisé. Source : [désactiver le diff sur les données sensibles](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_checkmode.html).

## TP 12 — Provisionner sans infrastructure

### 12.1 — P2 — L'inventaire Proxmox ne lit pas la bonne clé d'adresse

**Fichier :** [inventory.proxmox.yml](corrige/tp12-provisioning/proxmox/inventory.proxmox.yml), ligne 44.

L'expression utilise `.ip_addresses`, alors que le plugin produit une clé `ip-addresses`, avec des valeurs CIDR. L'accès échoue et `default(proxmox_name)` masque le défaut : l'adresse de connexion devient le nom de VM, sans garantie de résolution DNS.

**Correction :** lire `['ip-addresses']`, sélectionner une adresse du réseau attendu, exclure loopback/IPv6 si nécessaire et retirer le préfixe CIDR. Ne pas prendre aveuglément la première interface. **Confirmé dans le code du plugin installé et dans sa [source officielle 2.0.0](https://github.com/ansible-collections/community.proxmox/blob/2.0.0/plugins/inventory/proxmox.py).**

### 12.2 — P2 — Les tags décrits ne sont pas appliqués et le filtre dev n'existe pas

**Fichiers :** [creer-vm.yml](corrige/tp12-provisioning/proxmox/creer-vm.yml), variable `machines` et tâche d'update ; [inventory.proxmox.yml](corrige/tp12-provisioning/proxmox/inventory.proxmox.yml), ligne 29.

Chaque machine déclare `tags: [applicatif, dev]` ou `[cache, dev]`, mais aucune tâche ne transmet `item.tags` à Proxmox. Les groupes annoncés dépendent donc de tags éventuellement hérités du template, pas des données du TP. Le commentaire promet aussi de conserver les machines démarrées **et** étiquetées dev ; le filtre ne teste que `running`.

**Correction :** appliquer les tags, puis filtrer explicitement l'environnement. Source : [filtres et keyed_groups du plugin Proxmox](https://docs.ansible.com/projects/ansible/latest/collections/community/proxmox/proxmox_inventory.html).

### 12.3 — P2 — Le groupe d'état VMware utilise une propriété non collectée par défaut

**Fichier :** [inventory.vmware.yml](corrige/tp12-provisioning/vmware/inventory.vmware.yml), ligne 22.

`keyed_groups` lit `runtime.powerState`. Les propriétés par défaut du plugin `vmware.vmware.vms` incluent `summary.runtime.powerState`, pas `runtime.powerState`. Le groupe `etat_*` attendu n'est donc pas construit dans la configuration fournie.

**Correction :** utiliser `summary.runtime.powerState` ou demander explicitement la propriété voulue. Source : [propriétés du plugin vms](https://docs.ansible.com/projects/ansible/latest/collections/vmware/vmware/vms_inventory.html), également vérifiées avec `ansible-doc` local.

### 12.4 — P2 — La chaîne provisioning → inventaire → configuration est incomplète

**Fichiers :** [README](corrige/tp12-provisioning/README.md) et playbooks Proxmox/VMware.

La commande d'exécution réelle ne fournit pas l'inventaire dynamique avec `-i`. `meta: refresh_inventory` recharge les sources déjà sélectionnées ; il ne découvre pas automatiquement le fichier voisin. Aucun second play ne configure les machines créées. Les valeurs CPU/mémoire déclarées côté VMware ne sont pas utilisées non plus.

**Correction :** documenter l'inventaire à charger, ajouter le play de configuration annoncé et appliquer les ressources VMware, ou réduire explicitement la promesse au clonage. Pour la branche Proxmox réelle, déclarer également `netaddr`, nécessaire au filtre `ansible.utils.ipaddr` utilisé dans l'attente SSH.

Ces défauts n'empêchent pas le `--syntax-check` demandé dans ce TP hors infrastructure ; ils invalident une partie des comportements présentés comme prêts à l'emploi.

## TP 13 — Automatiser un routeur VyOS

### 13.1 — P1 — Le playbook configure une troisième interface absente de la topologie déclarée

**Fichiers :** [Vagrantfile](Vagrantfile), définition de `net01` et réseau commun ; [02-configuration.yml](corrige/tp13-reseau/playbooks/02-configuration.yml), lignes 14 et 22.

Le Vagrantfile ajoute un seul réseau privé au NAT. Le TP configure pourtant `eth1` **et** `eth2`. Aucune seconde carte de réseau privé/applicatif n'est déclarée pour `net01`. Sauf carte supplémentaire embarquée dans la box et non documentée, `eth2` n'existe pas et la configuration Ethernet est rejetée.

**Correction :** déclarer une carte additionnelle pour le réseau applicatif, ou limiter l'exercice aux interfaces réellement présentes. Vérifier les noms par la découverte avant mutation. **Incohérence de topologie confirmée ; contenu exact de la box à vérifier ultérieurement.** Source : [réseaux privés Vagrant](https://developer.hashicorp.com/vagrant/docs/networking/private_network).

### 13.2 — P1 — Les dépendances Python du parsing et de la connexion réseau manquent

**Fichiers :** [module 14](J3-Perimetres-Avances/14-Reseau.md), préparation ; [README TP 13](corrige/tp13-reseau/README.md).

Les commandes installent les collections, mais pas `ntc-templates` nécessaire au parseur choisi. `network_cli` nécessite aussi un backend Python SSH, `ansible-pylibssh` ou Paramiko, qui n'est pas garanti par `pipx install ansible`. Installer une collection Galaxy n'installe pas ces bibliothèques dans l'environnement Python d'Ansible.

**Correction :** avec le parcours pipx, ajouter par exemple `pipx inject ansible ntc-templates ansible-pylibssh`, fixer le backend et vérifier leurs imports dans l'interpréteur réellement utilisé. Sources : [parsing CLI](https://docs.ansible.com/projects/ansible/latest/network/user_guide/cli_parsing.html), [dépendances de network_cli](https://docs.ansible.com/projects/ansible/latest/collections/ansible/netcommon/network_cli_connection.html).

**Vérifié localement :** `03-hors-ligne.yml` réussit avec les bibliothèques déjà présentes sur ce poste et trouve trois interfaces actives. Cela ne valide pas la procédure d'installation sur un poste vierge.

### 13.3 — P2 — L'assertion ne vérifie ni les adresses ni l'idempotence

**Fichier :** [02-configuration.yml](corrige/tp13-reseau/playbooks/02-configuration.yml), ligne 56.

La tâche intitulée « Les adresses appliquees sont bien presentes » vérifie seulement qu'une entrée nommée `eth1` existe. Elle réussit même si l'adresse attendue n'y figure pas ; elle ignore `eth2`. Une relecture `gathered` ne démontre pas non plus qu'un second passage de configuration serait sans changement.

**Correction :** comparer les adresses normalisées au modèle attendu et rejouer la configuration pour contrôler `changed=0`. **Confirmé par lecture de l'assertion.**

**Réserve documentaire :** le constat de refus de `connection: local` correspond bien au plugin d'action VyOS installé. En revanche, les formulations « tous les resource modules exigent une cible » et « seule voie réellement hors ligne » sont trop générales. Limiter cette conclusion à la combinaison collection/version/transport vérifiée ; la [documentation vyos_interfaces](https://docs.ansible.com/projects/ansible/latest/collections/vyos/vyos/vyos_interfaces_module.html) décrit bien `rendered` et `parsed` comme des traitements hors ligne, d'où l'importance de distinguer le module de son plugin d'action.

## TP 14 — Cluster k3s et déploiement applicatif

### 14.1 — P1 — La préparation Python contredit l'installation pipx et PEP 668

**Fichiers :** [module 15](J3-Perimetres-Avances/15-Kubernetes.md), §3 et préparation ; [README TP 14](corrige/tp14-k3s/README.md).

Le TP prescrit `pip install 'kubernetes>=24.2.0' jsonpatch` dans le shell système. Sur le poste Ubuntu décrit, cette commande est refusée par le mécanisme `EXTERNALLY-MANAGED`, expliqué au TP 01. Même si elle réussit ailleurs, elle n'installe pas nécessairement dans le venv pipx d'Ansible.

**Correction :** utiliser `pipx inject ansible 'kubernetes>=24.2.0' jsonpatch` dans ce parcours et veiller à ce que les plays localhost utilisent cet interpréteur. Les commandes avec `-i localhost,` rendent particulièrement utile un `ansible_python_interpreter: "{{ ansible_playbook_python }}"` explicite. Sources : [environnements gérés extérieurement](https://packaging.python.org/en/latest/specifications/externally-managed-environments/), [prérequis k8s](https://docs.ansible.com/projects/ansible/latest/collections/kubernetes/core/k8s_module.html).

### 14.2 — P1 — Helm et kubectl ne sont pas installés sur le contrôleur

**Fichiers :** préparation du [module 15](J3-Perimetres-Avances/15-Kubernetes.md), [application.yml](corrige/tp14-k3s/application.yml).

Le TP appelle `kubectl` sur le poste et les modules Helm sur localhost, sans installer ces binaires. L'installation de k3s dans les VM ne les installe pas sur le contrôleur ; la collection `kubernetes.core` ne fournit pas le binaire Helm.

**Correction :** ajouter l'installation/version de Helm et de kubectl dans les prérequis et vérifier leur présence avant le TP. Source : [prérequis du module helm](https://docs.ansible.com/projects/ansible/latest/collections/kubernetes/core/helm_module.html).

### 14.3 — P1 — L'attente `Available=True` est appliquée aussi au Service et à l'Ingress

**Fichiers :** [application.yml](corrige/tp14-k3s/application.yml), ligne 85 ; [application.yaml.j2](corrige/tp14-k3s/templates/application.yaml.j2).

Le template contient trois documents : Deployment, Service et Ingress. Le module applique `wait_condition: {type: Available, status: 'True'}` à chaque ressource. Cette condition est adaptée au Deployment, mais pas au Service ClusterIP généré. L'attente finit par expirer sur le Service ; le play échoue avant de terminer le déploiement.

**Correction :** appliquer tous les manifestes sans cette condition commune, puis attendre séparément la disponibilité du Deployment. Vérifier ensuite le Service et l'Ingress avec des contrôles adaptés. **Confirmé par la logique du waiter de la collection locale**, qui cherche la condition demandée dans `status.conditions`. Source : [wait et wait_condition du module k8s](https://docs.ansible.com/projects/ansible/latest/collections/kubernetes/core/k8s_module.html).

### 14.4 — P1 — Le chart metrics-server entre en conflit avec celui intégré à k3s

**Fichiers :** [application.yml](corrige/tp14-k3s/application.yml), ligne 108 ; [defaults du rôle k3s](corrige/tp14-k3s/roles/k3s/defaults/main.yml), `k3s_desactiver: []`.

K3s déploie metrics-server par défaut. Le play installe ensuite un autre metrics-server avec `apiService.create: true`, qui revendique la même API agrégée `v1beta1.metrics.k8s.io`. Helm rencontre une ressource existante ne lui appartenant pas.

**Correction :** choisir un autre chart pour l'exercice, ou désactiver explicitement le composant intégré avant de le remplacer par Helm. Source : [composants empaquetés de K3s](https://docs.k3s.io/installation/packaged-components).

### 14.5 — P2 — Changer `k3s_version` ne met pas à niveau le cluster

**Fichier :** [roles/k3s/tasks/main.yml](corrige/tp14-k3s/roles/k3s/tasks/main.yml), ligne 77.

L'installation est protégée par `creates: /usr/local/bin/k3s`. Dès que le binaire existe, une nouvelle valeur de `k3s_version` n'est jamais appliquée. Un passage sans changement ne prouve donc pas que la version déclarée est respectée.

**Correction :** comparer la version installée à la version cible avant de relancer l'installateur, ou documenter explicitement que le rôle ne couvre que le bootstrap et refuse un écart de version. **Confirmé par le garde `creates`.**

### 14.6 — P2 — Le kubeconfig administrateur produit par le TP n'est pas ignoré par Git

**Fichiers :** [cluster.yml](corrige/tp14-k3s/cluster.yml), tâche d'écriture locale ; [.gitignore](.gitignore).

Le TP écrit `corrige/tp14-k3s/kubeconfig` dans le dépôt. Aucun motif ne l'exclut. Il contient des justificatifs d'accès administrateur au cluster ; le mode 0600 n'empêche pas `git add .` de le versionner. Le hook de recherche de clés privées ne doit pas être supposé reconnaître un certificat/une clé encodés en base64 dans un kubeconfig.

**Correction :** ignorer ce fichier généré ou le stocker hors du dépôt, puis vérifier avec `git check-ignore`. Le support lui-même indique déjà les pouvoirs de ce kubeconfig : l'oubli est dans la protection du fichier produit.

## Ordre de correction conseillé

1. Rendre le socle exécutable : paquets Rocky, variable de boucle TP 04, routage des contrôles HTTP, comptes PostgreSQL avant bases.
2. Rendre les validations fiables : simulations initiales, variables de patching, `fqdn`, chargement des variables Molecule et vérifications HTTP.
3. Compléter les environnements d'exécution : outils EE, dépendances Python, inventaires et clés propres à CI/Semaphore.
4. Corriger J3 : topologie VyOS, inventaires de provisioning, attente Kubernetes et conflit metrics-server.
5. Valider ensuite le parcours sur les boxes prévues, avec première exécution et second passage d'idempotence. Cette validation réelle reste à faire ; les succès de syntaxe et de lint rapportés ici ne la remplacent pas.
