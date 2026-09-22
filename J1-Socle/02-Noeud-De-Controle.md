# Module 02 — Nœud de contrôle et lab

> **Jour 1** · 60 min · Théorie + **TP 01**
> Prérequis : [module 01](01-Introduction.md).

## Objectifs

- Installer un nœud de contrôle Ansible à jour sur Ubuntu 26.04, sans passer par les dépôts
  de la distribution.
- Comprendre pourquoi PEP 668 interdit `pip install --user` et quelles sont les alternatives.
- Connaître la précédence des fichiers `ansible.cfg` et les options qui comptent.
- Démarrer le lab et joindre les quatre machines du jour 1.

---

## 1. Installer Ansible

### 1.1 Pourquoi pas `apt install ansible`

| Source | `ansible-core` fourni | Verdict |
|---|---|---|
| Ubuntu 26.04 `universe` | 2.20.1 | Une version de retard |
| Debian 13 | 2.19.4 | Fin de vie le 30 novembre 2026 |
| Rocky Linux 10 AppStream | 2.16.16 | Fin de vie amont depuis juillet 2025 |
| **PPA officiel Ansible** | **2.21.4** | À jour, mais lié à Ubuntu |
| **pipx / uv (PyPI)** | **2.21.4** | À jour et portable — **choix de la formation** |

Le décalage n'est pas cosmétique : `ansible-core` 2.19 a introduit une refonte du moteur de
templating, et 2.21 a supprimé des plugins (voir §1.4). Travailler sur une version dépassée
en formation reviendrait à enseigner des comportements obsolètes.

### 1.2 PEP 668 : la méthode `pip install --user` ne fonctionne plus

Ubuntu 26.04 marque son interpréteur système comme *externally managed*
(`/usr/lib/python3.14/EXTERNALLY-MANAGED`). Toute installation directe échoue :

```console
$ pip install ansible
error: externally-managed-environment
```

L'option `--break-system-packages` existe. **Ne l'utilisez pas** sur un nœud de contrôle :
elle mélange les paquets Python d'Ansible et ceux dont dépend le système (dont `apt` lui-même).

La réponse est l'isolation par environnement virtuel, automatisée par `pipx`.

### 1.3 Procédure retenue

```bash
# 1. pipx
sudo apt update && sudo apt install -y pipx
pipx ensurepath          # ajoute ~/.local/bin au PATH
exec $SHELL -l           # recharge le shell : indispensable

# 2. Le paquet communautaire Ansible (moteur + ~90 collections)
#    --include-deps est OBLIGATOIRE : sans lui, seuls les exécutables du paquet
#    `ansible` sont exposés, et `ansible-playbook` (fourni par ansible-core) manque.
#    La version est FIGÉE : sans elle, deux stagiaires n'ont pas le même moteur.
pipx install --include-deps 'ansible==14.4.*'

# 3. Outils de qualité, installés séparément (modules 09 et 10)
pipx install 'ansible-lint==26.8.*'
pipx install 'molecule==26.8.*'
```

> **Attention**
> Ne retirez pas ces contraintes de version. `pipx install ansible` sans version installe la
> dernière publiée, qui n'est pas forcément celle validée pour ce support. La même exigence
> s'applique aux collections, bornées à leur majeure dans `collections/requirements.yml`.

Chaque outil vit dans son propre environnement virtuel et n'expose que ses propres
exécutables : il n'y a donc pas de collision dans `~/.local/bin`.

> **Vérification**
> ```console
> $ ansible --version
> ansible [core 2.21.4]
>   python version = 3.14.x
> $ ansible-lint --version
> ansible-lint 26.8.0 using ansible-core:2.21.4
> ```
> Si `ansible-core` n'est pas en 2.21.x, `pipx ensurepath` n'a pas été pris en compte ou un
> paquet `apt` masque l'installation : contrôlez avec `which -a ansible`.

**Alternatives.**

- *Le plus rapide sur Ubuntu* : le PPA officiel, qui publie bien pour `resolute`.
  ```bash
  sudo add-apt-repository -y ppa:ansible/ansible
  sudo apt update && sudo apt install -y ansible
  ```
- *Tout-en-un* : `ansible-dev-tools` réunit `ansible-lint`, `molecule`, `ansible-navigator`,
  `ansible-builder`, `ansible-creator` et `ansible-sign`. Sa méthode d'installation
  documentée est `pip` dans un environnement virtuel ; sous pipx, il faut
  `pipx install --include-deps ansible-dev-tools` pour exposer les exécutables des
  dépendances. Il **n'apporte pas** les collections communautaires.
- *uv* : `uv tool install --with-executables-from ansible-core ansible` fonctionne, mais
  n'est pas documenté par le projet Ansible. Ne mélangez jamais pipx et uv pour un même outil.

### 1.4 Ce qui a disparu en 2.20 et 2.21

À connaître avant de reprendre du code existant :

| Élément | Statut | Remplacement |
|---|---|---|
| `ansible.builtin.paramiko_ssh` | **Supprimé en 2.21** (déprécié en 2.19) | `ansible.builtin.ssh`. Aucune collection ne le reprend. |
| Transport `smart` | Supprimé en 2.20 | `ssh` explicite |
| `ansible.builtin.include` | Supprimé en 2.16 | `include_tasks`, `import_tasks`, `import_playbook` |
| API Galaxy v2 dans `ansible-galaxy` | Supprimée en 2.20 | API v3 |
| `apt_key`, `apt_repository` | Dépréciés | `ansible.builtin.deb822_repository` |
| Python 3.11 sur le contrôleur | Abandonné en 2.20 | Python 3.12 minimum |

`ansible-core` 2.21 ne livre plus que **quatre** plugins de connexion :

```console
$ ansible-doc -t connection -l | grep ^ansible.builtin
ansible.builtin.local   execute on controller
ansible.builtin.psrp    Run tasks over Microsoft PowerShell Remoting Protocol
ansible.builtin.ssh     connect via SSH client binary
ansible.builtin.winrm   Run tasks over Microsoft's WinRM
```

## 2. Installer l'hyperviseur et Vagrant

### 2.1 VirtualBox — depuis le dépôt Oracle, pas depuis `multiverse`

Ubuntu 26.04 embarque le noyau Linux 7.0. La compilation du module `vboxdrv` échouait sur ce
noyau (`implicit declaration of function 'ASMCpuIdEx_EDX'`) jusqu'à VirtualBox **7.2.8**.
Le paquet `multiverse` d'Ubuntu 26.04 est en 7.2.6, **antérieur au correctif**, et il entre en
conflit avec le paquet Oracle. Utilisez le dépôt Oracle, qui fournit 7.2.18.

```bash
sudo apt install -y build-essential dkms linux-headers-generic

wget -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc \
  | sudo gpg --yes --output /usr/share/keyrings/oracle-virtualbox-2016.gpg --dearmor

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] \
https://download.virtualbox.org/virtualbox/debian resolute contrib" \
  | sudo tee /etc/apt/sources.list.d/virtualbox.list

sudo apt update && sudo apt install -y virtualbox-7.2
```

> **Attention — Secure Boot**
> Si Secure Boot est actif (`mokutil --sb-state`), le module `vboxdrv` non signé est refusé au
> chargement. Deux voies : désactiver Secure Boot dans le firmware (le plus simple en salle),
> ou enrôler une clé MOK avec `sudo dkms generate_mok` puis `sudo mokutil --import`, suivi d'un
> redémarrage et d'une validation dans l'écran bleu *MOKManager*.

Le réseau host-only `192.168.56.0/24` utilisé par le lab est autorisé par défaut : depuis
VirtualBox 6.1.28 la plage permise est `192.168.56.0/21`. Aucun `/etc/vbox/networks.conf`
n'est à créer. Si vous en créez un pour une autre plage, n'oubliez pas d'y **réautoriser**
celle-ci, faute de quoi plus aucune adresse n'est attribuée.

### 2.2 Vagrant

Vagrant n'existe plus dans les dépôts Ubuntu depuis la 24.04. Le dépôt HashiCorp publie pour
`resolute` (Vagrant 2.4.9, amd64 uniquement).

```bash
wget -O- https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com resolute main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update && sudo apt install -y vagrant
```

> **Attention — fin du registre de boxes**
> Vagrant est sous licence BUSL-1.1 depuis la 2.4.3 (usage formation couvert par
> l'*Additional Use Grant*). Surtout, **le registre HCP Vagrant ferme le 31 décembre 2026** :
> plus aucune publication depuis le 1er octobre 2026. Les boxes utilisées ici doivent être
> **téléchargées et conservées localement** avant cette échéance. En production, hébergez vos
> propres fichiers `.box` et référencez-les avec `box_url` et `box_download_checksum`.

## 3. Les exécutables

| Commande | Usage |
|---|---|
| `ansible` | Commande ad hoc, un seul module (module 03) |
| `ansible-playbook` | Exécution d'un playbook — la commande principale |
| `ansible-inventory` | Inspecter un inventaire : `--graph`, `--list`, `--host` |
| `ansible-doc` | Documentation hors ligne des modules et plugins |
| `ansible-config` | `list`, `dump`, `init` — introspection de la configuration |
| `ansible-galaxy` | Installer et publier rôles et collections (module 06) |
| `ansible-vault` | Chiffrer des variables et des fichiers (module 11) |
| `ansible-console` | Shell interactif sur un inventaire |
| `ansible-lint` | Analyse statique (module 09) |
| `ansible-navigator` | Interface texte, exécution en conteneur (module 10) |

`ansible-doc` est l'outil le plus rentable au quotidien : il décrit la version **installée**,
là où une recherche web renvoie souvent une version différente.

```bash
ansible-doc ansible.builtin.copy            # documentation complète
ansible-doc -s ansible.builtin.copy         # aide-mémoire des options
ansible-doc -t lookup -l                    # lister les plugins lookup
```

## 4. `ansible.cfg`

### 4.1 Précédence

Le **premier fichier trouvé gagne**, et les autres sont totalement ignorés — il n'y a pas de
fusion :

1. `$ANSIBLE_CONFIG` (variable d'environnement)
2. `./ansible.cfg` (répertoire courant)
3. `~/.ansible.cfg`
4. `/etc/ansible/ansible.cfg`

> **Attention**
> Ansible **ignore** un `ansible.cfg` situé dans un répertoire accessible en écriture à tous
> (*world-writable*), pour empêcher qu'un tiers y dépose une configuration malveillante. Si
> votre configuration semble sans effet, c'est la première chose à vérifier.

Comme c'est le répertoire **courant** qui compte, et non celui du playbook, lancez toujours vos
commandes depuis la racine du dépôt. C'est également ce qui rend valides les chemins relatifs
vers les clés SSH de Vagrant.

### 4.2 La configuration du projet

Le fichier [`ansible.cfg`](../ansible.cfg) à la racine du dépôt :

```ini
[defaults]
inventory  = inventories/dev/hosts.yml
roles_path = roles

callback_result_format    = yaml
show_task_path_on_failure = true
callbacks_enabled = ansible.posix.profile_tasks, ansible.posix.timer

interpreter_python = auto_silent
forks              = 10
host_key_checking  = True

[privilege_escalation]
become        = false
become_method = sudo
become_user   = root

[ssh_connection]
ssh_args   = -C -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=accept-new
pipelining = true
```

Quelques choix méritent une explication.

- **`callback_result_format = yaml`.** De nombreux tutoriels indiquent encore
  `stdout_callback = yaml`. Cela **ne fonctionne plus** : ce callback appartenait à
  `community.general` et a été supprimé en version 12.0.0. La mise en forme YAML est désormais
  une option du callback `default` livré avec `ansible-core`.
- **`collections_path` n'est pas défini.** Les collections sont installées dans le chemin par
  défaut à partir de `collections/requirements.yml`. Le confinement au projet
  (`collections_path = collections`) est introduit au module 10, avec la chaîne CI, là où il
  devient nécessaire.
- **`host_key_checking = True` avec `StrictHostKeyChecking=accept-new`.** Les tutoriels
  désactivent souvent la vérification des clés d'hôte. C'est une mauvaise habitude : elle
  supprime toute détection d'usurpation. `accept-new` accepte un hôte inconnu à la première
  connexion, mais refuse toujours une clé **qui a changé** — exactement le comportement voulu
  dans un lab où les VMs sont recréées.
- **`pipelining = true`.** Réduit le nombre d'opérations SSH par tâche. Incompatible avec
  `requiretty` dans `sudoers`, absent des distributions modernes.
- **`become = false`.** L'élévation de privilèges est demandée explicitement dans les plays qui
  en ont besoin, plutôt que subie partout.

`ansible-config` permet de vérifier ce qui est réellement pris en compte :

```bash
ansible-config view                          # le fichier effectivement chargé
ansible-config dump --only-changed           # ce qui diffère des valeurs par défaut
ansible-config dump --only-changed -t all    # idem, options de plugins comprises
ansible-config init --disabled -t all        # gabarit commenté de toutes les options
```

> **Attention**
> `ansible-config dump --only-changed` **n'affiche pas** les options appartenant à un plugin.
> `callback_result_format`, `ssh_args` et `pipelining` en font partie : elles sont bien
> appliquées, mais n'apparaissent qu'avec `-t all`. C'est une source de confusion classique
> lorsqu'on croit qu'un réglage n'a pas été pris en compte.

## 5. Le lab

Les sept machines sont décrites dans le [`Vagrantfile`](../Vagrantfile). Points de conception à
retenir :

- **Les versions de box sont épinglées.** `bento/rockylinux-10` est passée de BIOS à EFI entre
  la 10.0 et la 10.1 ; sans épinglage, deux stagiaires n'auraient pas la même machine.
- **Les trois VMs k3s ne démarrent pas** avec un `vagrant up` simple (`autostart: false`) : elles
  sont réservées au jour 3.
- **Le dossier partagé `/vagrant` est désactivé.** Ansible travaille en SSH et n'en a pas besoin.
  Cela évite la panne classique des cibles RHEL-like, où une mise à jour du noyau désaligne le
  module `vboxsf` et fait échouer le `vagrant up` suivant — exactement ce que fait le TP 06.
- **`bootstrap.sh` ne fait presque rien** : il garantit la présence de Python et l'accès `sudo`.
  Tout le reste est le travail des playbooks, c'est l'objet de la formation.

### Clés SSH

Vagrant génère une **clé distincte par machine**, déposée dans
`.vagrant/machines/<nom>/virtualbox/private_key`. L'inventaire exploite cette régularité avec
une seule ligne :

```yaml
ansible_ssh_private_key_file: ".vagrant/machines/{{ inventory_hostname }}/virtualbox/private_key"
```

Le chemin est relatif : il impose de lancer Ansible depuis la racine du dépôt.

---

## TP 01 — Mise en place du lab

**Durée : 30 min.** Corrigé : [`corrige/tp01-lab/`](../corrige/tp01-lab/)

### Objectif

Disposer d'un nœud de contrôle fonctionnel et joindre les quatre VMs du jour 1.

### Énoncé

1. **Installer le nœud de contrôle** (§1.3) et vérifier que `ansible --version` annonce
   `core 2.21.x` sur Python 3.12 ou supérieur.

2. **Installer VirtualBox et Vagrant** (§2). Vérifier :
   ```bash
   VBoxManage --version      # 7.2.x
   vagrant --version         # Vagrant 2.4.9
   ```

3. **Cloner le dépôt de formation et démarrer le lab.** Le premier démarrage télécharge deux
   boxes (environ 1,5 Go) : prévoyez le temps nécessaire.
   ```bash
   cd Formation-Ansible
   vagrant up
   vagrant status
   ```
   Les quatre machines `web01`, `web02`, `db01` et `tools` doivent être `running`.

4. **Écrire l'inventaire** `inventories/dev/hosts.yml` déclarant les quatre machines avec leur
   adresse sur le réseau host-only, l'utilisateur `vagrant` et le chemin de clé privée
   templatisé.

5. **Vérifier l'inventaire sans rien contacter :**
   ```bash
   ansible-inventory --graph
   ansible-inventory --host db01
   ```

6. **Joindre les machines :**
   ```bash
   ansible all -m ansible.builtin.ping
   ```
   Le module `ping` n'est pas un `ping` ICMP : il ouvre une connexion SSH, exécute un module
   Python sur la cible et attend la réponse `pong`. Il valide donc toute la chaîne.

7. **Première commande utile** — relever la version de chaque système :
   ```bash
   ansible all -m ansible.builtin.setup -a "filter=ansible_distribution*"
   ```

### Résultat attendu

```console
$ ansible all -m ansible.builtin.ping
web01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
...
```

### Pièges courants

| Symptôme | Cause | Correction |
|---|---|---|
| `Permission denied (publickey)` | Ansible lancé depuis un autre répertoire que la racine | `cd` à la racine du dépôt |
| `UNREACHABLE ... Connection timed out` | VM arrêtée, ou IP host-only erronée | `vagrant status`, vérifier `ansible_host` |
| `ansible-core 2.20` installé | Paquet `apt` prioritaire dans le PATH | `which -a ansible`, désinstaller le paquet apt |
| La configuration semble ignorée | Répertoire *world-writable*, ou mauvais répertoire courant | `ansible-config view` |
| `vagrant up` échoue sur `vboxdrv` | Secure Boot, ou VirtualBox antérieur à 7.2.8 | §2.1 |

### Pour aller plus loin

- Comparer `ansible-config dump --only-changed` avant et après avoir renommé `ansible.cfg`.
- Lancer `ansible all -m ansible.builtin.ping -vvv` et identifier, dans la trace, la commande
  SSH réellement exécutée ainsi que le réemploi de connexion par `ControlPersist`.

---

## Points clés

- Les paquets des distributions sont en retard : on installe avec **pipx**, pas avec `apt`.
- **PEP 668** interdit `pip install --user` ; `--break-system-packages` est à proscrire.
- **VirtualBox doit venir du dépôt Oracle** sur Ubuntu 26.04 (noyau 7.0).
- Le **registre de boxes Vagrant ferme le 31 décembre 2026** : conservez vos `.box`.
- `ansible.cfg` : **le premier fichier trouvé gagne**, et un répertoire *world-writable* le
  fait ignorer.
- `stdout_callback = yaml` est mort ; la bonne option est **`callback_result_format = yaml`**.
- `paramiko_ssh` a été **supprimé en 2.21** sans remplacement dans une collection.

---

**Module précédent :** [01 — Introduction](01-Introduction.md)
**Module suivant :** [03 — Inventaire et commandes ad hoc](03-Inventaire.md)
