# Module 13 — Provisioning : Proxmox, VMware et Terraform

> **Jour 3** · 105 min · Théorie + démonstration + **TP 12**
> Prérequis : [module 12](../J2-Industrialisation/12-WebUI.md).

## Objectifs

- Distinguer provisionner et configurer, et savoir quand chaque outil est pertinent.
- Créer des machines sur Proxmox VE avec `community.proxmox`.
- Connaître l'état des collections VMware et la migration en cours.
- Articuler Ansible avec Terraform ou OpenTofu.

> Ce module est théorique et démonstratif : le lab ne comporte ni Proxmox ni vCenter. Le TP
> consiste à écrire et valider le code, sans l'exécuter contre une infrastructure réelle.

---

## 1. Provisionner n'est pas configurer

| | Provisionner | Configurer |
|---|---|---|
| Objet | Créer, modifier, détruire une ressource | Amener un système existant à l'état voulu |
| Question | La machine existe-t-elle ? | Est-elle correctement réglée ? |
| Outils | Terraform, OpenTofu, Ansible, API du fournisseur | Ansible |
| État | Souvent un fichier d'état | Aucun |

La chaîne complète comporte quatre étapes :

```
Image             Machine              Inventaire            Configuration
(Packer)   →   (Terraform ou     →   (dynamique)    →    (Ansible)
                Ansible)
```

Ansible sait faire les étapes 2, 3 et 4. Il le fait bien en environnement sur site, où le
nombre de ressources est modeste et où l'on ne souhaite pas gérer de fichier d'état.

## 2. Proxmox VE

### La collection

**`community.proxmox` 2.0**, issue en 2025 d'une scission de `community.general`. Les anciens
noms `community.general.proxmox*` sont des redirections dépréciées, dont la suppression est
programmée.

Prérequis : `proxmoxer >= 2.3` et `requests` sur le nœud de contrôle. Proxmox VE 9.x.

| Module | Usage |
|---|---|
| `proxmox_kvm` | Machines virtuelles QEMU — le module central |
| `proxmox` | Conteneurs LXC |
| `proxmox_vm_info` | Interroger l'existant |
| `proxmox_template` | Gabarits et images |
| `proxmox_disk`, `proxmox_nic` | Disques et interfaces |
| `proxmox_snap`, `proxmox_backup` | Instantanés et sauvegardes |
| `proxmox_storage`, `proxmox_user`, `proxmox_access_acl` | Exploitation |

### Authentification par jeton

N'utilisez pas le mot de passe d'un compte. Créez un utilisateur dédié, un rôle limité, puis un
jeton d'API — révocable indépendamment.

```yaml
community.proxmox.proxmox_kvm:
  api_host: pve.lab.local
  api_user: ansible@pve
  api_token_id: automation
  api_token_secret: "{{ vault_proxmox_token }}"
```

Les variables d'environnement `PROXMOX_HOST`, `PROXMOX_USER`, `PROXMOX_TOKEN_ID` et
`PROXMOX_TOKEN_SECRET` sont reconnues.

> `validate_certs` vaut **`true`** par défaut depuis la version 2.0. Sur un Proxmox à certificat
> auto-signé, il faut le passer explicitement à `false` — ou mieux, installer un certificat.

### Cloner un gabarit et le personnaliser par cloud-init

Le schéma habituel : un gabarit Debian préparé avec cloud-init, cloné puis paramétré.

```yaml
- name: Cloner le gabarit
  community.proxmox.proxmox_kvm:
    node: pve01
    clone: debian13-cloudinit
    newid: "{{ item.vmid }}"
    name: "{{ item.nom }}"
    storage: local-lvm
    full: true
    timeout: 300
    state: present
  loop: "{{ machines }}"

- name: Configurer cloud-init
  community.proxmox.proxmox_kvm:
    node: pve01
    vmid: "{{ item.vmid }}"
    cores: "{{ item.cores }}"
    memory: "{{ item.memoire }}"
    ciuser: ansible
    sshkeys: "{{ lookup('ansible.builtin.file', '~/.ssh/id_ed25519.pub') }}"
    ipconfig:
      ipconfig0: "ip={{ item.ip }},gw={{ passerelle }}"
    nameservers: "{{ dns }}"
    update: true
    state: present
  loop: "{{ machines }}"
```

cloud-init évite d'avoir à se connecter à la machine pour l'amorcer : la clé SSH, l'utilisateur
et l'adresse sont injectés au premier démarrage. Ansible peut alors prendre la main.

Le paramètre `state` accepte `present`, `started`, `stopped`, `restarted`, `absent`, `template`,
`paused`, `hibernated`.

### L'inventaire dynamique

```yaml
# inventory.proxmox.yml
plugin: community.proxmox.proxmox
url: https://pve.lab.local:8006
user: ansible@pve
token_id: automation
token_secret: "{{ lookup('ansible.builtin.env', 'PROXMOX_TOKEN_SECRET') }}"
want_facts: true
qemu_extended_statuses: true
group_prefix: pve_
filters:
  - "proxmox_status == 'running'"
keyed_groups:
  - key: proxmox_tags_parsed
    prefix: tag
```

> **Attention**
> Le nom du fichier doit se terminer par `.proxmox.yml` pour que le greffon `auto` le
> reconnaisse.

Les **tags Proxmox deviennent des groupes Ansible**. C'est le point d'articulation entre
l'hyperviseur et l'automatisation : on étiquette une VM dans l'interface Proxmox, et elle entre
automatiquement dans le bon groupe.

Après création, `ansible.builtin.meta: refresh_inventory` recharge l'inventaire dans la même
exécution, ce qui permet d'enchaîner création et configuration sans écrire d'inventaire
statique.

La collection fournit aussi deux plugins de connexion : `proxmox_pct_remote` pour entrer dans un
conteneur LXC sans SSH, et `proxmox_qemu_api` qui passe par l'agent QEMU.

## 3. VMware vSphere

### Un paysage en recomposition

Trois collections coexistent, et c'est la principale difficulté.

| Collection | Statut 2026 | À utiliser ? |
|---|---|---|
| **`vmware.vmware`** 2.10 | Certifiée, en construction active | **Oui** — la cible |
| `community.vmware` 6.x | Dépend désormais de `vmware.vmware`, SDK `vcf-sdk` à la place de pyvmomi | Pour ce que la première ne couvre pas encore |
| `vmware.vmware_rest` 4.x | En retrait, nombreux modules dépréciés | Non |

> **Attention**
> `community.vmware.vmware_vm_inventory` est **déprécié** et sera retiré en version 7.0.0.
> Migrez vers `vmware.vmware.vms`. De nombreux modules `community.vmware` disparaîtront en
> version 8.0.0.

### Déployer depuis un gabarit

```yaml
- name: Deployer depuis le gabarit
  vmware.vmware.deploy_folder_template:
    hostname: "{{ vcenter_hostname }}"
    username: "{{ vcenter_username }}"
    password: "{{ vcenter_password }}"
    datacenter: DC-Noumea
    cluster: CL-Production
    datastore: DS-SSD-01
    template_name: debian13-template
    vm_name: "{{ item.nom }}"
    vm_folder: /DC-Noumea/vm/Formation
    power_on_after_deploy: true
  loop: "{{ machines }}"
```

Modules à connaître : `vm`, `vm_info`, `deploy_folder_template`,
`deploy_content_library_template`, `vm_apply_customization`, `vm_powerstate`, `vm_snapshot`,
`cluster_*`, `esxi_*`, `tags`.

Comme sur Proxmox, les **tags vSphere** alimentent les groupes de l'inventaire dynamique.

## 4. Ansible ou Terraform ?

**Terraform 1.16 / OpenTofu 1.12.** La formule courante, « Terraform provisionne, Ansible
configure », mérite d'être nuancée.

| Critère | Terraform / OpenTofu | Ansible |
|---|---|---|
| Fichier d'état | Obligatoire | Aucun |
| Prévisualisation | `plan` avant `apply` | `--check --diff`, moins complet |
| Suppression du superflu | Native | À écrire |
| Graphe de dépendances | Oui | Non, ordre explicite |
| Configuration interne | Faible | C'est son métier |
| Courbe d'apprentissage | Un langage de plus | Déjà acquise |

**Ansible seul suffit** quand l'infrastructure est modeste, sur site, peu interdépendante —
typiquement quelques dizaines de VMs sur Proxmox ou vSphere. On évite alors la gestion d'un
fichier d'état, qui est un actif critique à sauvegarder et à verrouiller.

**Terraform devient nécessaire** quand les ressources forment un graphe, quand la détection de
dérive doit être systématique, ou quand il faut détruire proprement un environnement entier.

### Les faire travailler ensemble

La collection `cloud.terraform` 4.x :

- le module `terraform` lance `plan` et `apply` depuis un playbook ;
- `terraform_output` récupère les sorties ;
- le greffon d'inventaire **`terraform_state`** construit l'inventaire **depuis le fichier
  d'état** ;
- `binary_path` permet d'utiliser OpenTofu à la place de Terraform.

```yaml
plugin: cloud.terraform.terraform_state
backend_type: http
```

Le découpage devient : Terraform crée, son état décrit ce qui existe, Ansible lit cet état comme
inventaire et configure. Aucune liste de machines n'est écrite à la main.

## 5. Les autres cibles

| Plateforme | Collection | Inventaire dynamique |
|---|---|---|
| AWS | `amazon.aws` 11.x | `aws_ec2`, `aws_rds` |
| Azure | `azure.azcollection` 3.x | `azure_rm` |
| Google Cloud | `google.cloud` 1.x | `gcp_compute` |
| KVM / libvirt | `community.libvirt` | `libvirt` |
| Docker | `community.docker` | `docker_containers` |
| Podman | `containers.podman` | — |

**Packer** complète l'ensemble en amont : son provisionneur Ansible permet de construire l'image
avec les mêmes rôles que ceux utilisés ensuite pour la configuration.

---

## TP 12 — Provisionner sans infrastructure

**Durée : 20 min.** Corrigé : [`corrige/tp12-provisioning/`](../corrige/tp12-provisioning/)

### Objectif

Écrire et valider le code de provisionnement, sans Proxmox ni vCenter. L'objectif est la
structure et la validation statique, pas l'exécution.

### Énoncé

1. **Écrire `proxmox/creer-vm.yml`** créant trois machines par clonage d'un gabarit :
   - play ciblant `localhost` en `connection: local` — les modules parlent à une API ;
   - authentification par **jeton**, le secret venant de l'environnement ou du vault ;
   - une assertion vérifiant que le secret est fourni ;
   - la liste des machines sous forme de **données** (nom, vmid, ip, cpu, mémoire, tags) ;
   - clonage, puis réglage des ressources et de cloud-init, puis démarrage ;
   - attente de l'ouverture du port 22 ;
   - `meta: refresh_inventory` pour enchaîner sur la configuration.

2. **Écrire `inventory.proxmox.yml`** : filtrage sur les machines démarrées, groupes issus des
   **tags Proxmox**, préfixe de groupe, variable calculée pour la mémoire.

3. **Écrire l'équivalent VMware** avec `vmware.vmware.deploy_folder_template` et le greffon
   d'inventaire `vmware.vmware.vms`.

4. **Valider** :
   ```bash
   ansible-playbook proxmox/creer-vm.yml --syntax-check
   ansible-lint proxmox/ vmware/
   ```

5. **Déclarer les collections** dans `collections/requirements.yml` et constater que
   `ansible-lint` échoue tant que ce n'est pas fait.

### Points d'attention

- Le play cible `localhost` : les modules dialoguent avec une API, ils ne se connectent pas aux
  VMs créées.
- Le nom de fichier d'inventaire doit se terminer par `.proxmox.yml`.
- `validate_certs` vaut `true` par défaut depuis `community.proxmox` 2.0.
- Les tags de l'hyperviseur deviennent des groupes : c'est le point d'articulation.
- `refresh_inventory` évite d'écrire un inventaire statique après création.

### Pièges courants

| Symptôme | Cause |
|---|---|
| `couldn't resolve module/action 'community.proxmox...'` | Collection non déclarée |
| Certificat refusé | `validate_certs: true` par défaut |
| Inventaire non reconnu | Nom de fichier ne finissant pas par `.proxmox.yml` |
| Machines créées mais non joignables | cloud-init non configuré, ou clé SSH absente |
| Modules `community.vmware` en avertissement | Migration vers `vmware.vmware` à faire |

### Pour aller plus loin

- Démonstration formateur sur un Proxmox réel : cycle complet création, configuration,
  destruction.
- Écrire le `main.tf` équivalent et comparer avec le playbook.
- Lire un `terraform.tfstate` avec le greffon `cloud.terraform.terraform_state`.

---

## Points clés

- **Provisionner ≠ configurer.** Ansible sait faire les deux ; Terraform ne fait que le premier.
- Les modules d'infrastructure s'exécutent sur le **nœud de contrôle**, contre une API.
- Sur Proxmox : **jeton d'API**, clonage de gabarit, **cloud-init** pour l'amorçage.
- Les **tags de l'hyperviseur deviennent des groupes Ansible**.
- `meta: refresh_inventory` enchaîne création et configuration sans inventaire statique.
- Côté VMware, la cible est **`vmware.vmware`** ; `vmware_vm_inventory` est déprécié.
- Ansible seul suffit sur site ; Terraform s'impose dès qu'il faut un graphe et un `plan`.

---

**Module précédent :** [12 — Interfaces web](../J2-Industrialisation/12-WebUI.md)
**Module suivant :** [14 — Automatisation réseau](14-Reseau.md)
