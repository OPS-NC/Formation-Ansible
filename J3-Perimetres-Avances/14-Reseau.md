# Module 14 — Automatisation réseau

> **Jour 3** · 90 min · Théorie + **TP 13**
> Prérequis : [module 13](13-Provisioning.md).

## Objectifs

- Comprendre ce qui change quand la cible n'a pas de Python.
- Utiliser `network_cli` et les *resource modules* avec leurs états.
- Analyser une configuration existante, y compris hors ligne.
- Situer NetBox comme source de vérité.

---

## 1. Ce qui change

Un commutateur ou un routeur n'a ni Python, ni `sudo`, ni système de fichiers accessible. Le
modèle d'exécution est donc inversé.

| | Serveur Linux | Équipement réseau |
|---|---|---|
| Où s'exécute le module | Sur la cible | **Sur le nœud de contrôle** |
| Connexion | `ssh` | `network_cli`, `netconf`, `httpapi`, `grpc` |
| Prérequis sur la cible | Python 3.9+ | Un accès CLI ou une API |
| Élévation de privilèges | `become: sudo` | Mode `enable`, quand il existe |
| Facts | `setup` | `<vendeur>_facts` |

```yaml
all:
  children:
    reseau:
      hosts:
        net01:
          ansible_host: 192.168.56.51
      vars:
        ansible_connection: ansible.netcommon.network_cli
        ansible_network_os: vyos.vyos.vyos
        ansible_user: vagrant
        ansible_become: false
```

`ansible_network_os` est la variable centrale : elle sélectionne les greffons `cliconf` et
`terminal` du constructeur, qui savent reconnaître l'invite, entrer en mode configuration et
valider.

### La collection `ansible.netcommon`

Socle commun à tous les constructeurs. Plugins de connexion : `network_cli` (SSH puis CLI),
`netconf` (XML sur SSH), `httpapi` (API REST), `grpc`, `libssh`.

Modules génériques, utiles quand aucun module dédié n'existe : `cli_command`, `cli_config`,
`cli_backup`, `cli_restore`, `netconf_get`, `netconf_config`.

> **Attention**
> `paramiko` a été retiré d'`ansible-core` 2.21. Côté réseau, `ansible.netcommon.network_cli`
> conserve une option `ssh_type: paramiko`, elle-même dépréciée au profit de `libssh`
> (`ansible-pylibssh`).

## 2. Les resource modules

C'est l'apport majeur de la dernière décennie côté réseau : au lieu d'envoyer des commandes, on
décrit un **modèle de données** et le module calcule les commandes.

```yaml
- name: Appliquer les adresses IP
  vyos.vyos.vyos_l3_interfaces:
    config:
      - name: eth1
        ipv4:
          - address: 192.168.56.51/24
    state: replaced
```

### Les huit états

| État | Effet |
|---|---|
| `merged` | Ajoute et modifie, **ne supprime rien**. Défaut, le plus sûr. |
| `replaced` | Remplace la configuration **des seuls objets cités** |
| `overridden` | Remplace **toute** la configuration de la ressource. Dangereux. |
| `deleted` | Supprime les objets cités |
| `purged` | Supprime l'objet lui-même, pas seulement sa configuration |
| `gathered` | **Lit** l'existant et le renvoie comme données. Ne modifie rien. |
| `rendered` | Produit les commandes **sans les appliquer** |
| `parsed` | Transforme une configuration texte en données |

Deux usages structurants :

- **`gathered` est la porte d'entrée d'une migration.** On lit la configuration d'un équipement
  existant, on obtient un modèle de données, on le versionne dans Git, puis on le pilote.
- **`overridden` mérite une revue.** Il supprime tout ce qui n'est pas décrit. C'est l'état qui
  garantit la conformité, et celui qui coupe un réseau si le modèle est incomplet.

> **Attention — `rendered` et `parsed` ne fonctionnent pas hors ligne**
> Leur documentation les présente comme des états « hors ligne ». En pratique, avec
> `ansible-core` 2.21 et les collections actuelles, ils **exigent malgré tout une cible
> joignable** :
> - avec `connection: local`, le module refuse : `Connection type local is not valid for this
>   module` — un garde-fou présent dans le greffon d'action depuis `cisco.ios` 4.0.0 ;
> - avec `network_cli`, ansible-core établit la connexion SSH **avant** d'exécuter le module,
>   car ce greffon déclare `force_persistence`.
>
> Le module lui-même n'ouvre pas de connexion pour ces deux états, mais le greffon l'a déjà
> fait. Aucun contournement documenté n'existe. Pour travailler réellement sans équipement,
> voyez la section 4.

## 3. Le paysage des collections

| Collection | Statut 2026 |
|---|---|
| `cisco.ios` 11.x, `cisco.nxos`, `cisco.iosxr` | Maintenues, dans le paquet Ansible |
| `arista.eos` 12.x | Maintenue, CLI et eAPI |
| `vyos.vyos` 6.x | Maintenue, testée sur VyOS 1.3, 1.4 et 1.5 |
| `fortinet.fortios` | Maintenue, `httpapi` |
| `community.routeros` | MikroTik, par l'API |
| `paloaltonetworks.panos`, `arubanetworks.aoscx` | Maintenues, hors paquet |
| **`junipernetworks.junos`** | **Archivée en mars 2026** → utiliser **`juniper.device`** |
| `dellemc.os10`, `arubanetworks.aos_switch` | Peu ou plus actives |
| `community.network` | Retirée, sans remplaçant |
| `frr.frr` | **Dépréciée, fin de vie décembre 2025**, incompatible `ansible-core` 2.21 |

## 4. Travailler sans équipement

Trois approches fonctionnent réellement.

### `cli_parse` avec `text:`

Quand on lui fournit un texte au lieu d'une commande, `ansible.utils.cli_parse` n'ouvre aucune
connexion. C'est l'outil de mise au point par excellence.

```yaml
- hosts: localhost
  connection: local
  tasks:
    - name: Transformer un "show ip interface brief" en donnees
      ansible.utils.cli_parse:
        text: "{{ lookup('ansible.builtin.file', 'fixtures/show-ip-int-brief.txt') }}"
        parser:
          name: ansible.netcommon.ntc_templates
          command: show ip interface brief
          os: cisco_ios
      register: analyse
```

Résultat obtenu sur une sortie de quatre interfaces :

```yaml
analyse.parsed:
  - interface: GigabitEthernet0/0
    ip_address: 192.168.56.1
    proto: up
    status: up
  - interface: GigabitEthernet0/2
    ip_address: unassigned
    proto: down
    status: administratively down
```

Analyseurs disponibles : `ntc_templates` et `textfsm` (dépendance `textfsm`), `ttp`, `pyats`,
`xml`, `json`, `native`.

### Jinja2 et validation par schéma

Générer la configuration par gabarit et valider le modèle de données avec
`ansible.utils.validate` (JSON Schema) ne dépend d'aucun greffon réseau.

### Tests unitaires de collection

C'est ainsi que les mainteneurs testent `rendered` et `parsed` : `ansible-test units` avec une
connexion simulée.

## 5. Le lab de la formation

La machine `net01` du `Vagrantfile` est un **VyOS**, routeur logiciel libre.

```bash
vagrant up net01
```

C'est la seule pile réseau libre qui fonctionne sous VirtualBox sans Docker, sans compte et sans
licence :

| Solution | Obstacle |
|---|---|
| Containerlab (SR Linux, cEOS) | Impose Docker sur l'hôte |
| Cisco CML-Free | Ne supporte **pas** VirtualBox ; compte Cisco obligatoire |
| GNS3, EVE-NG | Installation lourde ; EVE-NG Community en fin de vie |
| FRRouting | Collection `frr.frr` en fin de vie, incompatible 2.21 |
| **VyOS** | Box figée depuis août 2024, mais fonctionnelle |

## 6. Exploitation

### Sauvegarder avant de modifier

```yaml
- name: Sauvegarder la configuration courante
  vyos.vyos.vyos_config:
    backup: true
    backup_options:
      dir_path: ./sauvegardes
      filename: "net01-{{ '%Y%m%d-%H%M%S' | strftime }}.cfg"
```

C'est la première tâche de tout playbook réseau. Sans elle, il n'y a pas de retour arrière.

### Les autres précautions

- **`--check --diff`** fonctionne sur la plupart des resource modules : le différentiel montre
  les commandes qui seraient envoyées.
- **`serial: 1`** pour ne jamais toucher deux équipements du même chemin simultanément.
- **Fenêtre de maintenance** : une erreur de configuration réseau coupe l'accès à l'équipement,
  y compris pour Ansible.
- **`commit confirmed`** sur les plateformes qui le proposent : la configuration est annulée
  automatiquement si l'opérateur ne confirme pas.

### NetBox comme source de vérité

`netbox.netbox` 3.23 fournit le greffon d'inventaire `nb_inventory`, le lookup `nb_lookup` et
des modules d'écriture. Le cycle de conformité devient :

```
NetBox (intention)  →  Ansible  →  équipement
        ↑                              │
        └────── gathered (réalité) ────┘
```

On compare l'intention déclarée dans NetBox à la réalité relue par `gathered` : l'écart est la
dérive. NetBox 4.7 se déploie facilement dans une VM avec `netbox-docker`.

---

## TP 13 — Automatiser un routeur VyOS

**Durée : 25 min.** Corrigé : [`corrige/tp13-reseau/`](../corrige/tp13-reseau/)

### Objectif

Piloter un équipement réseau réel, puis analyser une configuration hors ligne.

### Préparation

```bash
vagrant up net01
ansible-galaxy collection install vyos.vyos ansible.netcommon ansible.utils
```

### Énoncé

1. **Écrire l'inventaire réseau** : `ansible_connection: ansible.netcommon.network_cli`,
   `ansible_network_os: vyos.vyos.vyos`, sans `become`.

2. **Découverte** (`01-decouverte.yml`) :
   - collecter les facts avec `vyos_facts`, sous-ensembles `interfaces`, `l3_interfaces`,
     `firewall_rules` ;
   - afficher nom, modèle et version ;
   - récupérer la configuration des interfaces avec **`state: gathered`** ;
   - la sauvegarder sur le nœud de contrôle. C'est le point de départ d'une migration.

3. **Configuration** (`02-configuration.yml`) :
   - **sauvegarder d'abord** avec `vyos_config` et `backup_options` ;
   - appliquer des descriptions d'interfaces en **`merged`** ;
   - appliquer des adresses IP en **`replaced`** ;
   - relire avec `gathered` et vérifier par une assertion.

4. **Comparer les états** : appliquer la même configuration en `merged`, puis en `overridden`,
   en `--check --diff` à chaque fois. Observer ce que le second supprimerait.

5. **Hors ligne** (`03-hors-ligne.yml`) :
   - analyser un `show ip interface brief` stocké dans un fichier avec `cli_parse` et
     `ntc_templates` ;
   - en extraire la liste des interfaces actives.

6. **Constater la limite** : tenter un `vyos_interfaces` avec `state: rendered` en
   `connection: local`, et lire le message de refus.

### Résultat attendu

```console
TASK [Resultat de l analyse] ***************************************************
ok: [localhost] =>
    msg: '3 interfaces actives : GigabitEthernet0/0, GigabitEthernet0/1, Vlan10'
```

### Points d'attention

- Pas de `become` sur un équipement réseau.
- La **sauvegarde précède toujours** la modification.
- `merged` n'enlève rien ; `overridden` enlève tout ce qui n'est pas décrit.
- `rendered` et `parsed` **exigent une cible joignable**, malgré leur appellation « hors ligne ».
- `cli_parse` avec `text:` est la seule voie réellement hors ligne.

### Pièges courants

| Symptôme | Cause |
|---|---|
| `Connection type local is not valid for this module` | Resource module avec `connection: local` |
| `ssh connect failed: Timeout` sur `rendered` | Le greffon `network_cli` se connecte avant le module |
| `become` en échec | Les équipements réseau n'ont pas de `sudo` |
| Configuration perdue | `overridden` sur un modèle incomplet |
| Équipement injoignable après exécution | Interface d'administration modifiée sans `commit confirmed` |

### Pour aller plus loin

- Déployer NetBox dans une VM et générer l'inventaire avec `nb_inventory`.
- Écrire un gabarit TextFSM maison pour une commande non couverte par `ntc_templates`.
- Comparer `gathered` avant et après une modification manuelle sur l'équipement : c'est la
  détection de dérive.

---

## Points clés

- Les modules réseau s'exécutent **sur le nœud de contrôle** ; `ansible_network_os` choisit les
  greffons du constructeur.
- Les **resource modules** décrivent des données, pas des commandes.
- `gathered` ouvre la migration ; `merged` est sûr ; `overridden` doit être relu.
- **`rendered` et `parsed` ne fonctionnent pas sans cible joignable**, contrairement à ce que
  leur nom suggère.
- **`cli_parse` avec `text:`** est la vraie voie hors ligne.
- `junipernetworks.junos` est archivée : utilisez `juniper.device`.
- **Sauvegarder avant de modifier**, toujours.

---

**Module précédent :** [13 — Provisioning](13-Provisioning.md)
**Module suivant :** [15 — Kubernetes avec Ansible](15-Kubernetes.md)
