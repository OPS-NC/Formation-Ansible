# Module 15 — Kubernetes avec Ansible

> **Jour 3** · 105 min · Théorie + **TP 14**
> Prérequis : [module 14](14-Reseau.md).

## Objectifs

- Savoir où Ansible reste pertinent face à Helm, ArgoCD et Flux.
- Monter un cluster k3s avec Ansible, en évitant le piège réseau du lab.
- Piloter des ressources Kubernetes avec `kubernetes.core`.
- Conduire des opérations de jour 2 sur les nœuds.

---

## 1. Où Ansible est pertinent

C'est la question à trancher avant d'écrire la moindre ligne.

| Besoin | Outil |
|---|---|
| **Amorcer** un cluster (paquets, noyau, conteneurs, certificats) | **Ansible** |
| **Jour 2 sur les nœuds** : correctifs, redémarrages, `drain` | **Ansible** |
| **Dépendances hors cluster** : DNS, répartiteur, stockage, PKI, registre | **Ansible** |
| **Installer ArgoCD ou Flux** la première fois | **Ansible** |
| Déployer une application, en continu | **ArgoCD / Flux** |
| Empaqueter une application | **Helm** |

La règle : **Ansible amène le cluster à exister et les nœuds à rester sains ; le GitOps gère ce
qui tourne dedans.**

Utiliser Ansible pour déployer en continu des manifestes revient à réécrire ArgoCD moins bien.
À l'inverse, ArgoCD ne sait pas mettre à jour le noyau d'un nœud ni configurer un pare-feu en
amont.

## 2. Monter un cluster

| Outil | Pour quoi |
|---|---|
| **k3s** + `k3s.orchestration` (dépôt k3s-io) | Lab, périphérie, petits clusters |
| **Kubespray** 2.31 | Production, kubeadm, haute disponibilité, Kubernetes 1.35 |
| `lablabs.rke2` | RKE2, contextes réglementés |
| kubeadm « maison » | Contrôle total, maintenance à votre charge |

> La collection officielle `k3s.orchestration` n'est **pas publiée sur Galaxy** : elle
> s'installe depuis son dépôt Git.
> ```yaml
> collections:
>   - name: https://github.com/k3s-io/k3s-ansible.git
>     type: git
>     version: "1.2.2"
> ```
> Le TP écrit son propre rôle, plus court et plus explicite sur le point suivant.

### Le piège du lab, à connaître absolument

Sous VirtualBox, chaque VM a deux interfaces : `eth0` en NAT, qui porte **10.0.2.15 sur toutes
les machines**, et `eth1` sur le réseau host-only. k3s déduit par défaut son adresse de la route
par défaut, donc du NAT.

Résultat : les trois nœuds s'enregistrent avec la **même** adresse. Le cluster paraît monter,
`kubectl get nodes` affiche `Ready`, puis le réseau des pods échoue **sans message d'erreur
explicite**.

Trois options l'évitent, sur le serveur **et** sur les agents :

```yaml
# /etc/rancher/k3s/config.yaml
node-ip: 192.168.56.41
flannel-iface: eth1
advertise-address: 192.168.56.41    # serveur uniquement
tls-san:
  - 192.168.56.41                   # serveur uniquement
```

> **Attention**
> Ne codez pas `eth1` en dur : le nom dépend de la distribution et des noms d'interfaces
> prévisibles. Cherchez l'interface qui porte réellement l'adresse attendue :
> ```yaml
> - name: Identifier l interface portant cette adresse
>   ansible.builtin.set_fact:
>     k3s_interface: "{{ item }}"
>   loop: "{{ ansible_facts['interfaces'] }}"
>   when:
>     - ansible_facts[item]['ipv4'] is defined
>     - ansible_facts[item]['ipv4']['address'] | default('') == k3s_node_ip
> ```
> Et n'utilisez **jamais** `ansible_default_ipv4` ici : c'est précisément le NAT.

### Fichier de configuration plutôt que variables d'installation

Le script d'installation accepte `INSTALL_K3S_EXEC`, mais `/etc/rancher/k3s/config.yaml` est
préférable : relisible, modifiable sans réinstaller, et naturellement idempotent avec
`template`. Les clés reprennent les options de la ligne de commande, sans les tirets.

```yaml
- name: Installer k3s
  ansible.builtin.command:
    cmd: /usr/local/bin/k3s-install.sh
    creates: /usr/local/bin/k3s
  environment:
    INSTALL_K3S_VERSION: "v1.36.4+k3s1"
    INSTALL_K3S_EXEC: "{{ 'server' if 'k3s_server' in group_names else 'agent' }}"
    K3S_TOKEN: "{{ k3s_token }}"
```

Le jeton est **généré à l'avance et poussé sur tous les nœuds**. Le lire sur le serveur
(`/var/lib/rancher/k3s/server/node-token`) créerait une dépendance d'ordre inutile.

### Récupérer le kubeconfig

`/etc/rancher/k3s/k3s.yaml` pointe vers `127.0.0.1` : utilisable sur le serveur, inutilisable
depuis le poste. On substitue l'adresse en le rapatriant.

```yaml
- name: Ecrire le kubeconfig localement
  ansible.builtin.copy:
    content: "{{ contenu.content | b64decode | replace('127.0.0.1', ansible_host) }}"
    dest: "{{ playbook_dir }}/kubeconfig"
    mode: "0600"
  delegate_to: localhost
  become: false
```

> `write-kubeconfig-mode: "0644"` est pratique en lab, à proscrire en production : ce fichier
> donne les pleins pouvoirs sur le cluster.

## 3. La collection `kubernetes.core`

**Version 6.6**, prérequis : le client Python `kubernetes >= 24.2.0`, plus `jsonpatch` sur le
nœud de contrôle.

> **Attention**
> Ces bibliothèques doivent être installées **dans l'environnement virtuel qui exécute Ansible**,
> pas dans le Python du système. Sur Ubuntu 26.04, `pip install` est d'ailleurs refusé par
> PEP 668 (module 02). Avec le parcours pipx : `pipx inject ansible 'kubernetes>=24.2.0'
> jsonpatch`. Les modules `helm` et les commandes `kubectl` du TP exigent en outre ces deux
> **binaires** sur le poste : ni k3s ni la collection ne les installent.

```bash
# `pip install` est refuse sur Ubuntu 26.04 (PEP 668, module 02). Les
# bibliotheques doivent entrer dans l'environnement virtuel d'Ansible.
pipx inject ansible 'kubernetes>=24.2.0' jsonpatch
ansible-galaxy collection install kubernetes.core

# Binaires appeles par les modules et par le TP, absents du parcours jusqu'ici
# kubectl : le paquet `kubernetes-client` N'EXISTE PAS dans Ubuntu 26.04
#   $ apt-cache policy kubernetes-client
#   kubernetes-client:
#     Installe : (aucun)
#     Candidat : (aucun)
# Le snap Canonical est la voie la plus courte ; en production, preferez le
# depot officiel pkgs.k8s.io, versionne par mineure de Kubernetes.
sudo snap install kubectl --classic
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

| Module | Usage |
|---|---|
| `k8s` | Créer, modifier, supprimer n'importe quelle ressource |
| `k8s_info` | Interroger |
| `k8s_drain` | Vider et réintégrer un nœud |
| `k8s_scale`, `k8s_exec`, `k8s_log` | Exploitation |
| `k8s_json_patch` | Modification chirurgicale |
| `helm`, `helm_repository`, `helm_template` | Charts Helm |
| `kubeconfig` | Manipuler le fichier de configuration |

> La version 6.0 a **supprimé** le greffon d'inventaire `k8s`. La compatibilité **Helm 4** est
> assurée depuis la 6.4 ; la 6.3 bornait explicitement Helm à la version 3.

### Manifestes paramétrés

L'apport principal face à `kubectl apply` : `template:` rend le gabarit Jinja2 **sur le nœud de
contrôle** avant l'envoi à l'API. Les manifestes deviennent paramétrables comme n'importe quel
fichier de configuration, avec les variables d'inventaire déjà en place.

```yaml
- name: Deployer l application
  kubernetes.core.k8s:
    kubeconfig: "{{ kubeconfig }}"
    state: present
    apply: true
    template: templates/application.yaml.j2
    wait: true
    wait_condition:
      type: Available
      status: "True"
    wait_timeout: 180
```

`apply: true` reproduit la sémantique de `kubectl apply`. `wait` avec `wait_condition` attend
que la ressource soit réellement disponible, et non simplement acceptée par l'API.

### Helm

```yaml
- name: Ajouter le depot
  kubernetes.core.helm_repository:
    name: bitnami
    repo_url: https://charts.bitnami.com/bitnami

- name: Installer le chart
  kubernetes.core.helm:
    kubeconfig: "{{ kubeconfig }}"
    name: metrics
    chart_ref: bitnami/metrics-server
    release_namespace: kube-system
    wait: true
    values:
      extraArgs:
        - --kubelet-insecure-tls
```

## 4. Le jour 2 sur les nœuds

C'est le domaine où Ansible n'a pas de concurrent : vider un nœud, intervenir sur le système,
puis le remettre en service.

```yaml
- name: Vider le noeud
  kubernetes.core.k8s_drain:
    name: k3s-node01
    state: drain
    delete_options:
      ignore_daemonsets: true
      delete_emptydir_data: true
      wait_timeout: 120

# Ici : mise à jour du noyau, redémarrage, changement de configuration système

- name: Remettre le noeud en service
  kubernetes.core.k8s_drain:
    name: k3s-node01
    state: uncordon
```

Combiné au `serial: 1` du module 07, on obtient une mise à jour glissante d'un cluster entier
sans interruption de service.

## 5. Ansible dans Kubernetes

L'inverse est aussi possible :

- un **execution environment** (module 10) exécuté comme `Job` ou `CronJob` ;
- `ansible-runner`, la bibliothèque qui exécute Ansible dans un EE — c'est elle qu'utilisent
  AWX et AAP ;
- l'**exécuteur Kubernetes** de Semaphore, en édition Enterprise ;
- l'**Ansible Operator SDK**, qui enveloppe des rôles dans un opérateur. Red Hat en déconseille
  l'usage pour de nouveaux projets.

---

## TP 14 — Cluster k3s et déploiement applicatif

**Durée : 50 min.** Corrigé : [`corrige/tp14-k3s/`](../corrige/tp14-k3s/)

### Préparation

```bash
vagrant up k3s-master k3s-node01 k3s-node02
# `pip install` est refuse sur Ubuntu 26.04 (PEP 668, module 02). Les
# bibliotheques doivent entrer dans l'environnement virtuel d'Ansible.
pipx inject ansible 'kubernetes>=24.2.0' jsonpatch
ansible-galaxy collection install kubernetes.core

# Binaires appeles par les modules et par le TP, absents du parcours jusqu'ici
# kubectl : le paquet `kubernetes-client` N'EXISTE PAS dans Ubuntu 26.04
#   $ apt-cache policy kubernetes-client
#   kubernetes-client:
#     Installe : (aucun)
#     Candidat : (aucun)
# Le snap Canonical est la voie la plus courte ; en production, preferez le
# depot officiel pkgs.k8s.io, versionne par mineure de Kubernetes.
sudo snap install kubectl --classic
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Énoncé

1. **Inventaire** : un groupe `k3s_server` (1 machine) et un groupe `k3s_agent` (2 machines),
   réunis sous `k3s_cluster`.

2. **Rôle `k3s`** :
   - déterminer l'adresse du nœud depuis `ansible_host` ;
   - **identifier l'interface** qui porte cette adresse, sans la coder en dur, et échouer
     explicitement si elle est introuvable ;
   - déposer `/etc/rancher/k3s/config.yaml` avec `node-ip` et `flannel-iface`, plus
     `advertise-address` et `tls-san` sur le serveur ;
   - installer k3s avec `creates` pour l'idempotence, le rôle venant de `INSTALL_K3S_EXEC` ;
   - démarrer le service, `k3s` ou `k3s-agent` selon le groupe ;
   - attendre que l'API réponde.

3. **`cluster.yml`** : trois plays — plan de contrôle, puis agents, puis récupération du
   kubeconfig avec substitution de `127.0.0.1`.

4. **Vérifier l'absence du piège** :
   ```bash
   export KUBECONFIG=corrige/tp14-k3s/kubeconfig
   kubectl get nodes -o wide
   ```
   Les trois nœuds doivent afficher **trois adresses internes distinctes** en 192.168.56.x. Si
   elles sont identiques ou en 10.0.2.15, la configuration n'a pas été prise en compte.

5. **`application.yml`** :
   - assertion sur la présence du kubeconfig ;
   - lister les nœuds avec `k8s_info` et **vérifier par assertion que leurs adresses internes
     sont distinctes** ;
   - créer un namespace ;
   - déployer Deployment, Service et Ingress depuis un **unique gabarit Jinja2** ;
   - attendre la disponibilité, puis vérifier le nombre de replicas ;
   - installer un chart Helm.

6. **`maintenance.yml`** : vider un nœud, vérifier qu'il est non ordonnançable, le remettre en
   service.

7. **Idempotence** : relancer les trois playbooks, aucun `changed` attendu.

### Points d'attention

- `node-ip` et `flannel-iface` sur **tous** les nœuds : c'est le point qui fait échouer la
  plupart des labs Kubernetes sous VirtualBox.
- `ansible_default_ipv4` désigne le NAT. Ne jamais s'en servir ici.
- Les modules `kubernetes.core` s'exécutent sur le **contrôleur** : le play cible `localhost`.
- Le jeton est poussé, pas lu depuis le serveur.
- Le kubeconfig récupéré doit voir son `127.0.0.1` remplacé.

### Pièges courants

| Symptôme | Cause |
|---|---|
| Les nœuds partagent la même adresse interne | `node-ip` absent |
| Les pods ne communiquent pas entre nœuds | `flannel-iface` absent |
| `kubectl` en échec depuis le poste | `127.0.0.1` non substitué dans le kubeconfig |
| `Unauthorized` sur le nœud serveur | `tls-san` sans l'adresse du lab |
| `ModuleNotFoundError: kubernetes` | Client Python absent du contrôleur |
| L'agent ne rejoint pas | Jeton différent, ou API pas encore prête |

### Pour aller plus loin

- Déployer ArgoCD avec le module `helm`, puis lui confier l'application : c'est le passage de
  relais entre Ansible et le GitOps.
- Ajouter `serial: 1` au playbook de maintenance pour une mise à jour glissante complète.
- Comparer avec la collection officielle `k3s.orchestration`.

---

## Points clés

- **Ansible amorce et maintient les nœuds ; ArgoCD et Flux gèrent les applications.**
- Sous VirtualBox, `node-ip` et `flannel-iface` sont **obligatoires**, sinon la panne est
  silencieuse.
- L'interface se **détecte** depuis les facts, jamais codée en dur.
- `/etc/rancher/k3s/config.yaml` vaut mieux que `INSTALL_K3S_EXEC`.
- `kubernetes.core` s'exécute sur le contrôleur ; `template:` rend les manifestes paramétrables.
- `k8s_drain` plus `serial: 1` donnent une mise à jour glissante du cluster.

---

**Module précédent :** [14 — Automatisation réseau](14-Reseau.md)
**Module suivant :** [16 — Event-Driven, IA, Windows](16-EDA-IA-Windows.md)
