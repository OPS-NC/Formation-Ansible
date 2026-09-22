# Module 11 — Gestion des secrets

> **Jour 2** · 45 min · Théorie + **TP 10**
> Prérequis : [module 10](10-Git-CICD.md).

## Objectifs

- Chiffrer des variables avec `ansible-vault` et gérer plusieurs environnements.
- Connaître les limites du vault et les alternatives.
- Éviter les fuites de secrets dans les journaux et les différentiels.

---

## 1. Le problème

Au TP 05, le mot de passe PostgreSQL est en clair dans `site.yml`. Trois conséquences : il est
visible de quiconque accède au dépôt, il apparaît dans l'historique Git pour toujours, et il
n'est pas rotatif sans modifier le code.

Trois familles de réponses, par sophistication croissante :

| Approche | Le secret est… | Adapté à |
|---|---|---|
| `ansible-vault` | Chiffré dans le dépôt | Petite et moyenne échelle |
| SOPS + age | Chiffré dans le dépôt, valeur par valeur | Revue de code, GitOps |
| Coffre externe | Hors du dépôt, lu à l'exécution | Grande échelle, rotation, audit |

## 2. ansible-vault

### Chiffrer un fichier

```bash
ansible-vault create   group_vars/db/vault.yml     # créer directement chiffré
ansible-vault encrypt  group_vars/db/vault.yml     # chiffrer un fichier existant
ansible-vault edit     group_vars/db/vault.yml     # éditer (déchiffre en mémoire)
ansible-vault view     group_vars/db/vault.yml     # afficher sans modifier
ansible-vault decrypt  group_vars/db/vault.yml     # déchiffrer définitivement
ansible-vault rekey    group_vars/db/vault.yml     # changer le mot de passe
```

Le fichier obtenu est du texte, versionnable :

```
$ANSIBLE_VAULT;1.2;AES256;dev
65353139393865386366326238623532373364383466636463623432336562623332656336353264
...
```

### La convention `vault_`

Chiffrer un fichier entier le rend illisible en revue de code. La pratique établie sépare le
quoi du combien :

```
group_vars/db/
├── main.yml     en clair, lisible, versionné, relu
└── vault.yml    chiffré, ne contient que des valeurs
```

```yaml
# main.yml — en clair
postgresql_base: formation
postgresql_compte: applicatif
postgresql_motdepasse: "{{ vault_postgresql_motdepasse }}"
```

```yaml
# vault.yml — chiffré
vault_postgresql_motdepasse: "MotDePasseDeDemonstration42"
```

Le fichier en clair documente **l'existence** de chaque secret et l'endroit où il est utilisé.
La revue de code reste possible, et un secret ajouté se repère immédiatement.

### Chiffrer une seule valeur

```bash
ansible-vault encrypt_string --vault-id dev@.vault_pass_dev 'cle-api' --name api_token
```

```yaml
api_token: !vault |
          $ANSIBLE_VAULT;1.2;AES256;dev
          65643530396438396361353035383662633633636132363231643932616561306238326333393862
          ...
```

Pratique pour un secret isolé, mais rapidement illisible. Au-delà de deux ou trois valeurs,
préférez un fichier `vault.yml`.

### Plusieurs environnements : `--vault-id`

Développement et production ne doivent pas partager le même mot de passe.

```bash
ansible-vault encrypt --vault-id dev@.vault_pass_dev   inventories/dev/group_vars/db/vault.yml
ansible-vault encrypt --vault-id prod@.vault_pass_prod inventories/prod/group_vars/db/vault.yml
```

L'identifiant est **inscrit dans l'en-tête du fichier**, ce qui permet à Ansible de choisir le
bon mot de passe :

```
$ANSIBLE_VAULT;1.2;AES256;dev
$ANSIBLE_VAULT;1.2;AES256;prod
```

```bash
ansible-playbook site.yml -i inventories/dev/ \
  --vault-id dev@.vault_pass_dev --vault-id prod@.vault_pass_prod
```

Fournir plusieurs identifiants est sans danger : Ansible n'utilise que celui qui correspond.
Avec le mauvais mot de passe :

```console
$ ansible-playbook site.yml --vault-id dev@/tmp/mauvais
ERROR! Decryption failed (no vault secrets were found that could decrypt).
```

### Fournir le mot de passe

| Méthode | Usage |
|---|---|
| `--ask-vault-pass` | Interactif |
| `--vault-password-file .vault_pass` | Fichier local, **jamais versionné** |
| `vault_password_file` dans `ansible.cfg` | Confort quotidien |
| Script exécutable renvoyant le mot de passe | Récupération depuis un coffre ou un trousseau |

```ini
[defaults]
vault_password_file = .vault_pass
```

Le fichier de mot de passe peut être un **script exécutable** : Ansible utilise sa sortie
standard. C'est ainsi qu'on récupère le mot de passe depuis un trousseau système ou un coffre,
sans jamais l'écrire sur disque.

### Les limites

- **Un mot de passe partagé par toute l'équipe.** Le départ d'une personne impose une rotation
  complète (`rekey`).
- **Pas de rotation fine** : le secret change dans le dépôt, donc dans un commit.
- **Différentiel inexploitable** : un fichier chiffré change entièrement à chaque modification.
  Une revue de code ne peut pas voir ce qui a bougé.
- **Aucune traçabilité** : le vault ne dit pas qui a lu quoi.

## 3. SOPS et age

SOPS chiffre **les valeurs** et laisse les clés en clair. Le différentiel redevient lisible :
on voit *quelle* variable a changé, sans voir sa valeur.

```yaml
postgresql_base: formation
postgresql_motdepasse: ENC[AES256_GCM,data:Tr7o3k...,type:str]
```

```bash
age-keygen -o age.key
sops --encrypt --age age1xyz... vault.yml > vault.sops.yml
sops vault.sops.yml          # édition transparente
```

La collection `community.sops` fournit le lookup, le module `load_vars` et un greffon de vars :

```yaml
- name: Lire un secret SOPS
  ansible.builtin.debug:
    msg: "{{ lookup('community.sops.sops', 'secrets/db.sops.yml') }}"
```

Avantages sur le vault : différentiels lisibles, plusieurs destinataires possibles (chaque
personne a sa propre clé), révocation individuelle sans tout rechiffrer.
Inconvénient : deux outils externes à installer et à gérer.

## 4. Coffres externes

Le secret n'est plus dans le dépôt du tout : il est lu à l'exécution.

```yaml
- name: Lire un secret depuis OpenBao ou HashiCorp Vault
  ansible.builtin.set_fact:
    db_password: >-
      {{ lookup('community.hashi_vault.hashi_vault',
                'secret=secret/data/db:password',
                url='https://vault.interne:8200',
                auth_method='jwt', role_id='ansible-ci') }}
```

`community.hashi_vault` fonctionne avec HashiCorp Vault et **OpenBao**. Authentification par
AppRole, ou par JWT/OIDC depuis la CI — le jeton est alors de courte durée et aucun secret
durable n'est stocké.

Autres greffons : `community.general.bitwarden_secrets_manager`,
`community.general.onepassword`, les gestionnaires de secrets des fournisseurs cloud.

Apports : rotation sans toucher au code, traçabilité des accès, révocation immédiate, droits
par machine ou par équipe. Coût : une infrastructure à exploiter, et une dépendance à sa
disponibilité au moment de l'exécution.

## 5. Hygiène

### `no_log`

```yaml
- name: Creer le compte applicatif
  community.postgresql.postgresql_user:
    name: "{{ postgresql_compte }}"
    password: "{{ postgresql_motdepasse }}"
  no_log: true
```

Sans `no_log`, le mot de passe apparaît dans la sortie en mode verbeux, dans le fichier de
journalisation et dans les artefacts de CI.

> **Attention**
> `no_log: true` masque **toute** la sortie de la tâche, y compris le message d'erreur. Pour
> déboguer, désactivez-le temporairement — jamais en production. Astuce :
> `no_log: "{{ not debug_secrets | default(false) }}"`.

### Les fuites les moins évidentes

| Source | Parade |
|---|---|
| `--diff` sur un fichier contenant un secret | `no_log: true` sur la tâche |
| Variable enregistrée puis affichée | Ne jamais `debug` un `register` de tâche sensible |
| Artefacts et journaux de CI | `no_log`, et nettoyage dans `after_script` |
| Cache de facts | Ne pas mettre de secret dans un `set_fact` mis en cache |
| Historique du shell | `ansible-vault encrypt_string` lit aussi l'entrée standard |
| Message de commit | Relecture avant poussée |

### Règles d'équipe

1. Le fichier de mot de passe vault est dans `.gitignore`, **toujours**.
2. Le hook `detect-private-key` est actif (module 10).
3. Un secret poussé sur un dépôt distant est **compromis** : on le change, on ne se contente pas
   de réécrire l'historique.
4. Les secrets de production ne sont jamais déchiffrables depuis un poste de développement.
5. Un compte de service par usage, avec le minimum de droits.

---

## TP 10 — Chiffrer les secrets du fil rouge

**Durée : 20 min.** Corrigé : [`corrige/tp10-secrets/`](../corrige/tp10-secrets/)

### Objectif

Sortir le mot de passe PostgreSQL du code en clair, avec deux environnements distincts.

### Énoncé

1. **Séparer le clair du chiffré** dans `inventories/dev/group_vars/db/` :
   - `main.yml` : `postgresql_base`, `postgresql_compte`, `postgresql_port`, et
     `postgresql_motdepasse` pointant vers `vault_postgresql_motdepasse` ;
   - `vault.yml` : les variables `vault_*`, chiffré avec `--vault-id dev@...`.

2. **Créer l'équivalent pour `prod`** avec un **mot de passe différent**.

3. **Vérifier l'en-tête** des deux fichiers : l'identifiant doit y figurer.

4. **Adapter `site.yml`** pour utiliser `postgresql_motdepasse`, et ajouter `no_log: true` sur
   la tâche de création du compte.

5. **Exécuter** en fournissant les deux identifiants :
   ```bash
   ansible-playbook site.yml -i inventories/dev/ \
     --vault-id dev@.vault_pass_dev --vault-id prod@.vault_pass_prod
   ```

6. **Provoquer l'échec** avec un mauvais mot de passe et lire le message.

7. **Chiffrer une valeur isolée** avec `encrypt_string` et l'insérer dans un fichier en clair.

8. **Tourner la clé** : `ansible-vault rekey --vault-id dev@... --new-vault-id dev@...`.

### Résultat attendu

```console
$ head -1 inventories/dev/group_vars/db/vault.yml
$ANSIBLE_VAULT;1.2;AES256;dev
$ head -1 inventories/prod/group_vars/db/vault.yml
$ANSIBLE_VAULT;1.2;AES256;prod

$ ansible-playbook ... --vault-id dev@/tmp/mauvais
ERROR! Decryption failed (no vault secrets were found that could decrypt).
```

### Points d'attention

- Les fichiers `.vault_pass*` sont dans `.gitignore` **avant** d'être créés.
- La convention `vault_` garde le fichier en clair lisible en revue.
- `no_log: true` masque toute la sortie de la tâche, message d'erreur compris.
- Fournir plusieurs `--vault-id` est sans risque : seul celui qui correspond est utilisé.

### Pièges courants

| Symptôme | Cause |
|---|---|
| `Decryption failed` | Mauvais mot de passe, ou identifiant non fourni |
| `ERROR! Attempting to decrypt but no vault secrets found` | Aucun mot de passe fourni |
| Le mot de passe apparaît dans la sortie | `no_log` absent |
| Le fichier `.vault_pass` est versionné | `.gitignore` incomplet |
| Différentiel illisible en revue | Fichier entièrement chiffré au lieu de la convention `vault_` |

### Pour aller plus loin

- Écrire un script de mot de passe vault lisant le trousseau du système, et le référencer dans
  `ansible.cfg`.
- Installer SOPS et age, chiffrer le même fichier, et comparer les différentiels Git.
- Démonstration formateur : lookup vers OpenBao avec authentification AppRole.

---

## Points clés

- Convention **`main.yml` en clair + `vault.yml` chiffré**, variables préfixées `vault_`.
- L'**identifiant de vault est inscrit dans le fichier** : un environnement, un mot de passe.
- Le fichier de mot de passe peut être un **script**, ce qui évite de l'écrire sur disque.
- Le vault ne donne **ni différentiel lisible, ni traçabilité, ni rotation fine**.
- **SOPS** chiffre les valeurs et rend la revue possible ; un **coffre externe** sort le secret
  du dépôt.
- `no_log: true` masque **tout**, message d'erreur inclus.
- Un secret poussé est compromis : on le change.

---

**Module précédent :** [10 — Git et CI/CD](10-Git-CICD.md)
**Module suivant :** [12 — Interfaces web](12-WebUI.md)
