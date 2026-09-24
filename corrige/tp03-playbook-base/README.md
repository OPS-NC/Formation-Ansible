# TP 03 — Premier playbook multi-OS

Énoncé : [module 04](../../J1-Socle/04-Playbooks.md#tp-03--premier-playbook-multi-os)

## Contenu

```
playbooks/
├── base.yml              11 tâches, appliquées à l'identique sur Debian 13 et Rocky 10
└── templates/
    └── hosts.j2          /etc/hosts du parc, généré depuis groups['all'] et hostvars
```

Ce TP réutilise l'inventaire du [TP 02](../tp02-inventaire/), enrichi de la variable
`paquet_ntp` dans `group_vars/debian.yml` et `group_vars/rocky.yml`.

## Prérequis

```bash
ansible-galaxy collection install -r collections/requirements.yml
ssh-keygen -t ed25519 -C "formation-ansible" -f ~/.ssh/id_ed25519 -N ""
```

## Vérification

Depuis la racine du dépôt :

```bash
I=corrige/tp02-inventaire/inventories/dev/hosts.yml
P=corrige/tp03-playbook-base/playbooks/base.yml

ansible-playbook -i $I $P --syntax-check
ansible-lint corrige/tp03-playbook-base/

ansible-playbook -i $I $P          # 1re convergence : la machine est vierge
ansible-playbook -i $I $P          # idempotence : changed=0
ansible-playbook -i $I $P --check --diff   # audit de derive, desormais possible
```

> ⚠️ **L'ordre n'est pas interchangeable.** Sur une machine vierge, `--check` ne peut pas valider
> l'ensemble du playbook : les paquets n'y sont pas installes, donc les taches qui portent sur
> le service ou le compte qu'ils fournissent echouent. La simulation prend tout son sens
> **apres** la premiere convergence, comme audit de derive. Voir
> [module 04](../../J1-Socle/04-Playbooks.md#--check--le-mode-simulation).

## Ce que le corrigé illustre

| Technique | Tâche |
|---|---|
| Gabarit Jinja2 alimenté par l'inventaire | `Generer /etc/hosts pour l ensemble du parc` |
| Différences de distribution portées par les variables | `Installer les paquets de base` |
| Lookup exécuté sur le nœud de contrôle | `Lire la cle publique du poste de travail` |
| Tolérance à un fichier absent (`errors='ignore'`) | idem |
| Validation avant mise en place (`visudo`) | `Autoriser sudo sans mot de passe` |
| Commande de lecture non idempotente encadrée | `Relever la version du noyau` |
