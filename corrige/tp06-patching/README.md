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

```bash
P=corrige/tp06-patching/playbooks/patching.yml
I=corrige/tp02-inventaire/inventories/dev/hosts.yml

ansible-lint corrige/tp06-patching/
ansible-playbook -i $I $P --check --diff
ansible-playbook -i $I $P
cat corrige/tp06-patching/rapport-patching.json
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
| Debian | `test -f /var/run/reboot-required` | 0 |
| RHEL / Rocky | `dnf needs-restarting -r` | 1 |

> À confirmer sur la VM Rocky 10 : `needs-restarting` est intégré à dnf5 sur EL10, alors qu'il
> provenait du paquet `dnf-utils` sur les versions antérieures.

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
