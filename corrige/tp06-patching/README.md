# TP 06 — Mise à jour orchestrée du parc

Énoncé : [module 07](../../J2-Industrialisation/07-Execution-Avancee.md#tp-06--mise-à-jour-orchestrée-du-parc)

## Contenu

```
playbooks/patching.yml                  2 plays : mise à jour puis rapport
inventories/dev/group_vars/
├── debian.yml                          commande et code retour de détection
└── rocky.yml                           idem pour la famille RHEL
```

Ces `group_vars` **complètent** ceux du [TP 02](../tp02-inventaire/). Pour les utiliser
ensemble, passez les deux inventaires :

```bash
ansible-playbook \
  -i corrige/tp02-inventaire/inventories/dev/hosts.yml \
  -i corrige/tp06-patching/inventories/dev/ \
  corrige/tp06-patching/playbooks/patching.yml
```

## Vérification

Les DEUX sources d'inventaire sont indispensables : la seconde porte
`maj_commande_reboot` et `maj_rc_reboot_requis`, sans lesquelles la detection
du redemarrage echoue.

```bash
P=corrige/tp06-patching/playbooks/patching.yml
I1=corrige/tp02-inventaire/inventories/dev/hosts.yml
I2=corrige/tp06-patching/inventories/dev/

ansible-lint corrige/tp06-patching/
ansible-playbook -i $I1 -i $I2 $P --check --diff
ansible-playbook -i $I1 -i $I2 $P
cat corrige/tp06-patching/rapport-patching.json
```

Verification rapide du chargement des variables :

```bash
ansible-inventory -i $I1 -i $I2 --host db01 | grep maj_
```

## Ce que le corrigé illustre

| Technique | Emplacement |
|---|---|
| Une machine à la fois | `serial: 1` |
| Arrêt au premier échec | `max_fail_percentage: 0` |
| Remise en état garantie | `always:` |
| Interruption contrôlée | `rescue:` puis `fail` |
| Attente active d'un service | `until` / `retries` / `delay` |
| Redémarrage avec attente du retour | `ansible.builtin.reboot` |
| Rapport consolidé sur le contrôleur | `run_once` + `delegate_to: localhost` + `become: false` |
| Association machine → état | `dict(zip(hosts, hosts \| map('extract', hostvars, 'cle')))` |

## Détection du redémarrage requis

Le mécanisme diffère par nature entre les deux familles, pas seulement par une valeur.
Les variables de groupe portent **la commande et le code retour attendu**, et le playbook
normalise le résultat dans une variable unique.

| Famille | Commande | Code retour signifiant « redémarrage requis » |
|---|---|---|
| Debian | comparaison noyau courant / plus récent noyau installé | 1 |
| RHEL / Rocky | `dnf needs-restarting -r` | 1 |

> **`/var/run/reboot-required` est un mécanisme Ubuntu, pas Debian.** Ce fichier est déposé
> par le crochet apt du paquet `update-notifier-common`, **absent de Debian 13** :
>
> ```console
> $ apt-cache policy update-notifier-common
> update-notifier-common:
>   Installed: (none)
>   Candidate: (none)
> ```
>
> Vérifié sur `bento/debian-13` : aucun crochet de `/etc/apt/apt.conf.d` ni de `/etc/kernel`
> ne mentionne `reboot-required`, et le fichier n'apparaît jamais. Tester sa présence
> répondait donc **toujours** « aucun redémarrage nécessaire » : la branche Debian du TP ne se
> déclenchait jamais, quel que soit le noyau installé.
>
> Le test retenu compare le noyau **en cours d'exécution** au plus récent noyau **installé**,
> via `linux-version` (paquet `linux-base`, présent sur toute installation Debian). Il ne
> couvre que le noyau, c'est-à-dire précisément ce qui impose un *redémarrage* ; les services
> à *redémarrer* sont une autre question, à laquelle répond `needrestart`.

> Vérifié sur Rocky 10 : le sous-commande `dnf needs-restarting` vient de
> **`python3-dnf-plugins-core`**, tiré par `dnf-plugins-core` (BaseOS) — déjà présent dans la
> box `bento/rockylinux-10`. Attention, le binaire autonome `/usr/bin/needs-restarting` est lui
> fourni par `yum-utils` : ce n'est pas le même chemin d'appel. Rocky 10 est resté sur **DNF4** ;
> ni `dnf5` ni `python3-libdnf5` n'y sont distribués.

## Le paquet qui pose une question

`grub-pc` redemande son disque d'installation à chaque mise à jour. La box `bento/debian-13`
est livrée **sans réponse enregistrée** (`grub-pc/install_devices` vide,
`grub-pc/install_devices_failed_upgrade` à `true`). En mode non interactif la question ne peut
pas être posée, et la mise à jour complète s'arrête :

```
You must correct your GRUB install devices before proceeding
dpkg: error processing package grub-pc (--configure)
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

Le playbook enregistre la réponse dans debconf **avant** la mise à jour. Le disque est porté
par `maj_disque_amorcage` dans `group_vars/debian.yml`, comme toute différence de parc.

## Le paquet qui pose une question

`grub-pc` redemande son disque d'installation à chaque mise à jour. La box `bento/debian-13`
est livrée **sans réponse enregistrée** (`grub-pc/install_devices` vide,
`grub-pc/install_devices_failed_upgrade` à `true`). En mode non interactif la question ne peut
pas être posée, et la mise à jour complète s'arrête :

```
You must correct your GRUB install devices before proceeding
dpkg: error processing package grub-pc (--configure)
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

Le playbook enregistre la réponse dans debconf **avant** la mise à jour. Le disque est porté
par `maj_disque_amorcage` dans `group_vars/debian.yml`, comme toute différence de parc.

## Rapport produit

```json
{
    "date": "2026-09-22T09:14:11.695319",
    "redemarrage_requis": {
        "db01": false,
        "web01": true,
        "web02": false
    }
}
```
