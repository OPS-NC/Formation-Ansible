# Audit technique — points restants

Audit initial du 22 septembre 2026. **Tous les constats ont été traités** ; ce fichier ne
conserve que ce qui reste ouvert, c'est-à-dire ce qui ne peut pas être tranché sans exécuter le
lab sur de vraies machines.

L'historique des corrections est dans les commits `fix: corrections issues de l'audit technique`
et suivants.

---

## Ce qui a été vérifié

| Contrôle | Résultat |
|---|---|
| `ansible-lint --profile production corrige/` | 90 fichiers, zéro violation |
| `--syntax-check` des 14 playbooks | tous valides |
| Résolution d'un secret chiffré jusqu'au rôle | vérifiée sur `db` et sur `ops` |
| Analyse réseau hors ligne (`cli_parse`) | exécutée, 3 interfaces détectées |
| Variable composée `fqdn` de l'inventaire construit | présente |
| Configuration Molecule (`molecule list`) | acceptée |
| Syntaxe Ruby du `Vagrantfile`, unicité des IP | valides |
| Liens internes des 35 fichiers Markdown | aucun cassé |
| Workflow GitHub de lint | au vert |

## Ce qui n'a jamais été exécuté

**Aucune VM, aucun conteneur, aucun cluster n'a été démarré.** Ni VirtualBox, ni Vagrant, ni
Podman, ni `ansible-builder` n'étaient disponibles sur le poste de rédaction. Aucun playbook
n'a été appliqué à une machine distante, même en simulation.

Les succès de syntaxe et de lint ci-dessus **ne remplacent pas** cette validation.

---

## Points ouverts, par ordre de priorité

### 1 — Validation de bout en bout du lab

Rien ne remplace un `vagrant up` suivi d'une application complète du fil rouge, puis d'un second
passage pour l'idempotence. À dérouler dans l'ordre des TP, sur le poste Ubuntu 26.04.

Points de contrôle à noter au passage :

- démarrage des huit VMs, compilation des modules VirtualBox sur le noyau 7.0, accès SSH ;
- premier passage **réel** avant toute simulation (voir module 04) ;
- second passage sans aucun `changed`.

### 2 — Faits à confirmer sur les images

| À vérifier | Où | Conséquence si faux |
|---|---|---|
| `dnf needs-restarting -r` et ses codes retour sur Rocky 10 | TP 06 | Détection de redémarrage erronée |
| Présence d'un producteur de `/var/run/reboot-required` sur `bento/debian-13` | TP 06 | Aucun redémarrage jamais déclenché |
| Emplacement réel du serveur nginx par défaut sur Rocky | rôle `nginx`, `vars/main.yml` | L'assertion Molecule passe sans rien prouver |
| Présence d'une seconde carte réseau sur la box `vyos/current` | TP 13 | `eth2` inexistante malgré le Vagrantfile |
| Disponibilité de la box `vyos/current` (figée depuis août 2024) | TP 13 | TP réseau impraticable |

### 3 — Exécutions non tentées

| Sujet | TP | Ce qui reste à prouver |
|---|---|---|
| `molecule test` complet avec Podman | 08 | Seule la configuration a été validée |
| Construction de l'execution environment | 09 | `ansible-builder` absent du poste de rédaction |
| Molecule dans un exécuteur de CI | 09 | Conteneurs imbriqués et privilèges |
| Installation de Semaphore sur la VM | 11 | Rôle écrit d'après le code source 2.19.12 |
| Provisioning Proxmox et vSphere | 12 | Aucune infrastructure disponible |
| Playbooks VyOS 01 et 02 | 13 | Seul le playbook hors ligne a tourné |
| Cluster k3s et déploiement applicatif | 14 | Aucun cluster monté |

### 4 — Choix assumés, à revoir si le contexte change

- **`postgres_port` ne configure que le pare-feu.** Le rôle installe un serveur en écoute locale
  et ne touche ni `listen_addresses`, ni `pg_hba.conf`. C'est documenté dans ses défauts et sa
  spécification d'arguments. Ouvrir la base au réseau est un exercice d'extension.
- **Le fichier `MAINTENANCE` du TP 06 est un témoin.** Aucun répartiteur du lab ne le consulte.
- **Les blocs `location` de proxy du TP 04 n'ont pas de backend.** Les interroger renvoie un 502,
  ce qui est annoncé. L'objet du TP est le rendu de configuration.
- **La box `vyos/current` est figée depuis août 2024.** Suffisante pour le TP, mais à reconstruire
  depuis `vyos-contrib/packer-vyos` pour travailler sur VyOS 1.5.
- **Le registre de boxes Vagrant ferme le 31 décembre 2026.** Les fichiers `.box` doivent être
  miroités en interne avant cette date.

---

## Méthode

Chaque constat de l'audit initial a été reproduit dans les fichiers du dépôt avant correction.
Les affirmations factuelles — paquets Rocky 10, clé de l'inventaire Proxmox, propriété VMware,
composants intégrés à k3s — ont été recoupées dans les dépôts et le code source des greffons,
et non reprises de confiance.

Une explication initialement retenue sur le comportement d'`ansible-lint` a été **écartée** faute
de reproductibilité : seule la cause réellement reproduite est documentée.
