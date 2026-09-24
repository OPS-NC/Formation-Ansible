# TP 11 — Déployer et exploiter Semaphore UI

Énoncé : [module 12](../../J2-Industrialisation/12-WebUI.md#tp-11--déployer-et-exploiter-semaphore-ui)

## Contenu

```
semaphore.yml                    playbook, ciblant le groupe ops
roles/semaphore/
├── defaults/main.yml            version, chemins, compte administrateur
├── tasks/main.yml               16 tâches, installation non interactive
├── handlers/main.yml
├── templates/config.json.j2
└── templates/semaphore.service.j2
```

## Vérification

```bash
I=corrige/tp02-inventaire/inventories/dev/hosts.yml
ansible-lint corrige/tp11-semaphore/
ansible-playbook -i $I corrige/tp11-semaphore/semaphore.yml
ansible-playbook -i $I corrige/tp11-semaphore/semaphore.yml   # idempotence
```

Interface : `http://192.168.56.31:3000`, compte `admin`, mot de passe défini par
`semaphore_admin_motdepasse` (valeur par défaut `changeme-formation`, à chiffrer au vault).

## Ce que le corrigé résout

| Difficulté | Traitement |
|---|---|
| Le `.deb` ne fournit que le binaire | Le rôle crée le compte, les répertoires et l'unité systemd |
| `semaphore setup` est interactif | `config.json` généré par gabarit, puis `semaphore migrate` |
| Clés de chiffrement non rejouables | Lues depuis la configuration existante, générées au premier passage seulement |
| `semaphore user add` non idempotent | `semaphore user list` interrogé avant création |
| Chemin de la base SQLite | Clé `sqlite.host`, et non `sqlite.name` |
| Paquet Community vs Pro | `semaphore_community_*.deb` explicitement retenu |

## Détails vérifiés

| Élément | Valeur |
|---|---|
| Version | 2.19.12 (30 août 2026) |
| Paquet Community | `semaphore_community_2.19.12_linux_amd64.deb` |
| Dialectes supportés | `sqlite`, `mysql`, `postgres` — BoltDB supprimé en 2.19 |
| Clés de chiffrement | 32 octets aléatoires encodés base64, soit 44 caractères |
| Webhook | `POST /api/integrations/<alias>` |
| Unité systemd fournie par le paquet | Aucune |

> Les variables `SEMAPHORE_ADMIN`, `SEMAPHORE_ADMIN_PASSWORD` et suivantes ne sont lues que par
> le script d'entrée de l'image Docker. Sur une installation par paquet, elles sont sans effet.

> ✅ **Validé** sur la VM `tools` (Debian 13) : installation complète en 18 s, puis second
> passage `changed=0`.
>
> ```console
> $ systemctl is-active semaphore
> active
> $ curl -s -o /dev/null -w '%{http_code}' http://192.168.56.31:3000/
> 200
> $ curl -s http://192.168.56.31:3000/api/ping
> pong
> $ semaphore user list --config /etc/semaphore/config.json
> admin
> $ /opt/semaphore-venv/bin/ansible --version
> ansible [core 2.21.4]
> ```
>
> L'environnement virtuel dédié exécute donc bien le même moteur que le poste de travail.
>
> 🚧 **Non validé** : l'usage de l'interface elle-même (création de projet, clés, tâches,
> webhook), qui relève de la manipulation en salle.
