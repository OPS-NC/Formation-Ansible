# Module 16 — Event-Driven Ansible, assistants IA, Windows

> **Jour 3** · 45 min · Théorie et démonstrations
> Prérequis : [module 15](15-Kubernetes.md).

## Objectifs

- Comprendre le modèle événementiel et ses cas d'usage réels.
- Situer les assistants IA de 2026 et les encadrer.
- Savoir administrer des serveurs Windows avec Ansible.

---

## 1. Event-Driven Ansible

### Du push au déclenchement

Ansible fonctionne en *push* (module 01) : rien ne se produit tant que personne ne lance
l'exécution. Event-Driven Ansible ajoute une boucle de réaction : une source d'événements, des
règles, des actions.

```
Source          Règle                         Action
Alertmanager →  si alerte = DiskFull      →   playbook de purge
Webhook      →  si branche = main         →   playbook de déploiement
Kafka        →  si type = scale_request   →   ajout d'un nœud
Journal      →  si erreur répétée 5 fois  →   redémarrage du service
```

### Un rulebook

```yaml
---
- name: Remediation automatique
  hosts: all
  sources:
    - ansible.eda.webhook:
        host: 0.0.0.0
        port: 5000

  rules:
    - name: Redemarrer nginx si le service est signale en panne
      condition: event.payload.service == "nginx" and event.payload.state == "failed"
      action:
        run_playbook:
          name: playbooks/redemarrer-nginx.yml

    - name: Alerter au-dela de trois occurrences
      condition: event.payload.count > 3
      action:
        run_job_template:
          name: escalade-astreinte
```

```bash
ansible-rulebook --rulebook rulebooks/remediation.yml -i inventories/dev/hosts.yml
```

**`ansible-rulebook` 1.3**, Python 3.9 à 3.12, et un **JDK** — le moteur de règles repose sur
Drools. C'est une contrainte d'exploitation à anticiper.

Sources disponibles : webhook, Kafka, Alertmanager, journal de fichiers, file AWS SQS, Azure
Service Bus, ServiceNow, sondage d'URL.

### Ce qu'il faut en attendre

| Bon usage | Mauvais usage |
|---|---|
| Remédiation d'incidents connus et documentés | Remplacer la supervision |
| Déploiement déclenché par Git | Boucler sans garde-fou |
| Réaction à une alerte d'infrastructure | Automatiser un incident mal compris |

> **Attention**
> Une remédiation automatique qui redémarre un service en boucle masque la panne au lieu de la
> traiter. Prévoyez toujours un compteur d'occurrences et une escalade vers un humain.

En édition gratuite, `ansible-rulebook` s'exécute en ligne de commande ou comme service. AAP
fournit l'**EDA Controller**, qui ajoute interface, droits et supervision des rulebooks.

## 2. Les assistants IA

### L'offre Red Hat

**Ansible Lightspeed a été renommé « Automation coding assistant ».** Inclus dans l'abonnement
AAP, il fonctionne avec IBM watsonx Code Assistant, Google Gemini, Red Hat AI, ou tout point
d'accès compatible OpenAI depuis fin 2025 — c'est le mode *apportez votre propre modèle*.

Un **serveur MCP officiel** (`aap-mcp-server`) expose AAP à un assistant : inventaires, modèles
de tâches, exécutions. La collection `ansible.mcp` permet l'inverse, appeler un serveur MCP
depuis un playbook.

### Les options gratuites

- Le **serveur MCP intégré à l'extension VS Code** `redhat.ansible`.
- Des **serveurs MCP communautaires**.
- Les assistants généralistes : Copilot, Claude Code, Cursor.

### Ce qui marche, et ce qui ne marche pas

Un assistant est très efficace pour produire la structure répétitive d'un rôle, convertir un
script shell en tâches, écrire un gabarit Jinja2, ou expliquer un message d'erreur.

Il échoue de façon caractéristique sur :

| Défaut | Manifestation |
|---|---|
| **Modules inventés** | Un module plausible qui n'existe pas |
| **FQCN erronés** | `community.general.nginx` au lieu du bon nom |
| **Options périmées** | `stdout_callback = yaml`, `apt_key`, `paramiko_ssh` |
| **Idempotence ignorée** | `shell:` sans `changed_when` |
| **Sécurité négligée** | Secrets en clair, `host_key_checking` désactivé |

Ces erreurs viennent du corpus d'entraînement, qui contient beaucoup de contenu ancien. Ce
module en a rencontré plusieurs pendant la préparation de cette formation.

> **La parade est déjà en place.** `ansible-lint` au profil `production` (module 09) rejette les
> FQCN inexistants, les modules inconnus et les `command` non encadrés. Molecule vérifie que le
> rôle fonctionne réellement. **Un assistant sans chaîne de qualité est un générateur de dette ;
> avec elle, c'est un gain de temps réel.**

Deux règles d'hygiène : ne jamais coller de secret dans un prompt, et vérifier chaque module
proposé avec `ansible-doc` avant de l'accepter.

## 3. Windows

Ansible administre Windows depuis longtemps ; ce qui a changé récemment, c'est le transport.

### Trois transports

| Plugin | Protocole | Quand l'utiliser |
|---|---|---|
| `winrm` | WS-Man | Historique, encore répandu |
| `psrp` | WS-Man | **À préférer à `winrm`** : plus rapide, meilleure gestion des proxys |
| `ssh` | OpenSSH | **Supporté officiellement depuis `ansible-core` 2.18** |

SSH natif exige OpenSSH 7.9 ou supérieur, donc **Windows Server 2022 et au-delà** en pratique.
Il faut passer le shell par défaut à PowerShell et le déclarer :

```yaml
ansible_connection: ssh
ansible_shell_type: powershell
```

### Inventaire type

```yaml
windows:
  hosts:
    srv-app01:
      ansible_host: 10.0.1.20
  vars:
    ansible_connection: psrp
    ansible_user: ansible@LAB.LOCAL
    ansible_psrp_auth: kerberos
    ansible_port: 5986
    ansible_psrp_cert_validation: ignore
```

### Collections et points d'attention

`ansible.windows` 3.8 fournit `win_feature`, `win_service`, `win_updates`, `win_package`,
`win_copy`, `win_file`, `win_regedit`, `win_user`. `community.windows` complète, et
`chocolatey.chocolatey` gère les paquets.

- Cibles supportées : Windows Server 2016 et ultérieur, PowerShell 5.1 minimum.
- Le **double saut** (se connecter puis accéder à une ressource réseau tierce) exige Kerberos
  avec délégation — c'est la difficulté classique.
- Les chemins s'écrivent avec des barres obliques inverses, à protéger en YAML.
- Il n'existe **pas** de nœud de contrôle Windows : le contrôleur reste Linux ou macOS, WSL2
  accepté.

---

## Points clés

- **Event-Driven Ansible** ajoute la réaction à événement au modèle *push*. `ansible-rulebook`
  exige un JDK.
- Prévoyez toujours **compteur et escalade** : une remédiation en boucle masque la panne.
- **Ansible Lightspeed s'appelle désormais Automation coding assistant** et accepte votre propre
  modèle.
- Les assistants inventent des modules et proposent des options périmées :
  **`ansible-lint` et Molecule sont la parade**, et elle est déjà en place.
- Sous Windows, préférez **`psrp`** à `winrm` ; **SSH natif est supporté depuis 2.18** sur
  Server 2022 et au-delà.

---

**Module précédent :** [15 — Kubernetes avec Ansible](15-Kubernetes.md)
**Module suivant :** [17 — Synthèse et feuille de route](17-Synthese.md)
