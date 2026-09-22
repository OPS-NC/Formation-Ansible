# TP 10 — Chiffrer les secrets du fil rouge

Énoncé : [module 11](../../J2-Industrialisation/11-Secrets.md#tp-10--chiffrer-les-secrets-du-fil-rouge)

## Contenu

```
site.yml                       playbook du fil rouge, consommant les secrets chiffrés
inventories/
├── dev/group_vars/
│   ├── db/
│   │   ├── main.yml           en clair : noms, ports, indirection vers le secret
│   │   └── vault.yml          chiffré, vault-id `dev`
│   └── ops/
│       ├── main.yml           configuration Semaphore en clair
│       └── vault.yml          mot de passe administrateur Semaphore, chiffré
└── prod/group_vars/db/
    ├── main.yml
    └── vault.yml              chiffré, vault-id `prod` (mot de passe différent)
playbooks/demo-secrets.yml
```

> **Un secret vit dans le groupe qui le consomme.** Le mot de passe Semaphore est dans
> `group_vars/ops/`, et non `group_vars/db/` : une variable de groupe n'est visible que par les
> machines de ce groupe. Placé au mauvais endroit, il resterait indéfini au TP 11.

## Mots de passe de démonstration

Les secrets chiffrés ici sont **factices**. Les mots de passe de vault sont publiés pour que
vous puissiez ouvrir les fichiers :

| Environnement | vault-id | Mot de passe |
|---|---|---|
| dev | `dev` | `formation` |
| prod | `prod` | `formation-prod` |

En situation réelle, ces mots de passe ne sont évidemment jamais versionnés.

## Vérification

```bash
printf 'formation\n'      > /tmp/vp_dev
printf 'formation-prod\n' > /tmp/vp_prod

D=corrige/tp10-secrets

# L'identifiant est inscrit dans l'en-tête du fichier
head -1 $D/inventories/dev/group_vars/db/vault.yml    # ...;AES256;dev
head -1 $D/inventories/prod/group_vars/db/vault.yml   # ...;AES256;prod

# Lecture du contenu
ansible-vault view --vault-id dev@/tmp/vp_dev $D/inventories/dev/group_vars/db/vault.yml

# Lecture par un playbook
ansible-playbook \
  -i corrige/tp02-inventaire/inventories/dev/hosts.yml \
  -i $D/inventories/dev/ \
  --vault-id dev@/tmp/vp_dev --vault-id prod@/tmp/vp_prod \
  $D/playbooks/demo-secrets.yml
```

## Résultats obtenus

Lecture réussie, seule la longueur du mot de passe est affichée :

```
msg: base=formation compte=applicatif longueur_mot_de_passe=27
```

Avec un mauvais mot de passe, `ansible-vault view` sort en **code retour 1**. Le message a
changé de forme en `ansible-core` 2.21 : il est désormais chaîné par un `<<< caused by >>>`.

```console
$ ansible-vault view --vault-id dev@/tmp/mauvais dev/group_vars/db/vault.yml ; echo $?
[ERROR]: Failed to view '.../vault.yml': Decryption failed (no vault secrets were
found that could decrypt).

Failed to view '.../vault.yml'.

<<< caused by >>>

Decryption failed (no vault secrets were found that could decrypt).
1
```

Un **playbook** lancé avec le mauvais mot de passe sort en **code retour 4** : la source
d'inventaire qui contient le fichier chiffré ne peut pas être analysée, et plus aucune machine
n'est jointe.

```console
[WARNING]: Unable to parse .../tp10-secrets/inventories/dev as an inventory source
```

Ne confondez pas les deux : 1 pour l'outil `ansible-vault`, 4 pour `ansible-playbook`.

## Ce que le corrigé illustre

| Point | Emplacement |
|---|---|
| Séparation clair / chiffré | `main.yml` et `vault.yml` |
| Convention de préfixe `vault_` | `vault_postgresql_motdepasse` |
| Indirection documentant le secret | `postgresql_motdepasse: "{{ vault_... }}"` |
| Un mot de passe par environnement | vault-id `dev` et `prod` |
| Identifiant inscrit dans le fichier | en-tête `$ANSIBLE_VAULT;1.2;AES256;<id>` |
| Affichage sans divulgation | `| length` au lieu de la valeur |

## Chiffrer une valeur isolée

```bash
ansible-vault encrypt_string --vault-id dev@/tmp/vp_dev 'cle-api' --name api_token
```

```yaml
api_token: !vault |
          $ANSIBLE_VAULT;1.2;AES256;dev
          65643530396438396361353035383662633633636132363231643932616561306238326333393862
```
