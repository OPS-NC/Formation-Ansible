# TP 13 — Automatiser un routeur VyOS

Énoncé : [module 14](../../J3-Perimetres-Avances/14-Reseau.md#tp-13--automatiser-un-routeur-vyos)

## Contenu

```
inventories/reseau.yml            connexion network_cli, sans become
playbooks/
├── 01-decouverte.yml             facts, gathered, sauvegarde de l'existant
├── 02-configuration.yml          backup, merged, replaced, vérification
└── 03-hors-ligne.yml             cli_parse sur un fichier, sans équipement
fixtures/
└── show-ip-interface-brief.txt   sortie CLI de référence
```

## Préparation

```bash
vagrant up net01
ansible-galaxy collection install vyos.vyos ansible.netcommon ansible.utils

# Bibliotheques Python : une collection Galaxy n'installe PAS ses dependances.
#   ntc-templates      : gabarits d'analyse utilises par cli_parse
#   ansible-pylibssh   : transport SSH de network_cli (paramiko a ete retire
#                        d'ansible-core 2.21)
pipx inject ansible ntc-templates ansible-pylibssh

# Enregistrer la cle d'hote du routeur AVANT la premiere connexion.
# Indispensable : network_cli passe par libssh, qui ignore le
# StrictHostKeyChecking=accept-new de l'ansible.cfg (reserve au client
# OpenSSH). L'option host_key_auto_add, elle, appartenait a paramiko, RETIRE
# d'ansible-core 2.21 : elle n'a plus aucun effet.
# Sans cette etape :
#   libssh: The authenticity of host '192.168.56.51' can't be established
#
# La forme HACHEE (`ssh-keyscan -H`) n'est PAS lue par libssh : ne pas
# l'utiliser ici. A rejouer apres chaque `vagrant destroy net01`.
ssh-keygen -R 192.168.56.51
ssh-keyscan 192.168.56.51 >> ~/.ssh/known_hosts
```

### Ce que la box impose

| Point | Valeur | Conséquence si ignoré |
|---|---|---|
| Compte SSH | `vyos` — il n'existe **aucun** compte `vagrant` | `Access denied` |
| Authentification | clé `~/.vagrant.d/insecure_private_keys/vagrant.key.**rsa**` | la clé `ed25519` est refusée : la box date d'août 2024 |
| Clé par machine | **non** — `insert_key` est désactivé dans le `Vagrantfile` | VyOS régénère ses `authorized_keys` au démarrage ; `vagrant reload` casserait l'accès |
| Configuration | sous le compte `vyos`, **jamais** en root | un `commit` lancé par root laisse le système de configuration en échec : tout `set` ultérieur répond `Set failed` |

## Vérification

```bash
D=corrige/tp13-reseau

# Avec l'équipement
ansible-playbook -i $D/inventories/reseau.yml $D/playbooks/01-decouverte.yml
ansible-playbook -i $D/inventories/reseau.yml $D/playbooks/02-configuration.yml --check --diff
ansible-playbook -i $D/inventories/reseau.yml $D/playbooks/02-configuration.yml

# Sans équipement, exécutable dès maintenant
ansible-playbook -i localhost, $D/playbooks/03-hors-ligne.yml
```

## Résultat obtenu hors ligne

```
msg: '3 interfaces actives : GigabitEthernet0/0, GigabitEthernet0/1, Vlan10'
```

Le modèle de données produit par `cli_parse` :

```yaml
- interface: GigabitEthernet0/0
  ip_address: 192.168.56.1
  proto: up
  status: up
- interface: GigabitEthernet0/2
  ip_address: unassigned
  proto: down
  status: administratively down
```

## La limite des états dits « hors ligne »

`rendered` et `parsed` sont documentés comme des traitements hors ligne. **Mesuré** avec
`vyos.vyos` 6.0 sur `ansible-core` 2.21, contre une adresse volontairement injoignable
(`203.0.113.254`, TEST-NET-3) :

| Tentative | Résultat |
|---|---|
| `connection: local` | **échoue** : `Connection type local is not valid for this module` |
| `ansible_connection: ansible.netcommon.network_cli` | **fonctionne** : rendu en 1,1 s, sans ouvrir de session SSH |

```console
$ ansible-playbook -i inventaire-injoignable.yml rendered.yml
TASK [vyos_interfaces state rendered]
ok: [fantome]
    r.rendered:
    - set interfaces ethernet eth1 description 'Aucun equipement'
    - set interfaces ethernet eth2 description 'Reseau applicatif'
fantome : ok=1 changed=0 unreachable=0 failed=0
```

Autrement dit, la contrainte n'est **pas** qu'il faille un équipement : c'est que le greffon
d'action des collections réseau refuse toute connexion autre que `network_cli`. Il suffit donc
de **déclarer** `network_cli` — l'équipement, lui, n'a pas besoin d'exister.

> **Attention au piège de précédence.** Une variable d'inventaire `ansible_connection` l'emporte
> sur le mot-clé `connection:` du play. Un play qui déclare `connection: local` sur un hôte dont
> l'inventaire porte `ansible_connection: network_cli` utilise en réalité **`network_cli`** : on
> croit alors tester le mode local alors qu'on parle à l'équipement. C'est exactement ainsi qu'on
> conclut à tort que `rendered` exige une machine joignable.

Conséquence pratique : `rendered` est utilisable hors ligne pour vérifier ce qu'un modèle de
données produirait. Pour analyser une sortie CLI existante, `cli_parse` avec `text:` reste la
bonne voie, comme le fait `03-hors-ligne.yml`.

## Pourquoi VyOS

| Solution | Obstacle en lab VirtualBox |
|---|---|
| Containerlab (SR Linux, cEOS) | Impose Docker sur l'hôte |
| Cisco CML-Free | Ne supporte pas VirtualBox, compte Cisco requis |
| FRRouting | Collection `frr.frr` en fin de vie, incompatible ansible-core 2.21 |
| **VyOS** | Box `vyos/current` figée depuis août 2024, mais fonctionnelle |

> **Validé** contre un VyOS réel (`vyos/current` 20240817.00.20, VyOS 1.5-rolling-202408170020).
> La box est bien disponible au téléchargement, et la seconde carte `eth2` existe.
>
> ```
> 01-decouverte     ok=5 changed=1 failed=0
>                   msg: vyos modele=VirtualBox version=VyOS 1.5-rolling-202408170020
> 02-configuration  ok=7 changed=3 failed=0
>                   assertions d'adresses ET d'idempotence au vert
> 03-hors-ligne     ok=4 changed=0 failed=0
> ```
>
> Y parvenir a demandé six corrections, décrites dans les commits `fix(tp13)` : plage
> host-only, détection de l'invité, adressage des interfaces, insertion de clé SSH, compte
> et type de clé, et provisionnement non privilégié.
>
> **Non validé** : NetBox comme source de vérité, et les états `rendered` / `parsed` hors
> ligne, dont la limite est décrite plus bas.
