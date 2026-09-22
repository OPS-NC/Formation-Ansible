# TP 14 — Cluster k3s et déploiement applicatif

Énoncé : [module 15](../../J3-Perimetres-Avances/15-Kubernetes.md#tp-14--cluster-k3s-et-déploiement-applicatif)

## Contenu

```
inventories/k3s.yml           1 serveur, 2 agents
cluster.yml                   montage du cluster et récupération du kubeconfig
application.yml               namespace, Deployment/Service/Ingress, chart Helm
maintenance.yml               drain et uncordon d'un nœud
roles/k3s/                    rôle d'installation
templates/application.yaml.j2 manifeste unique paramétré
```

## Préparation

```bash
vagrant up k3s-master k3s-node01 k3s-node02
pip install 'kubernetes>=24.2.0' jsonpatch
ansible-galaxy collection install kubernetes.core
```

## Vérification

```bash
K=corrige/tp14-k3s

ansible-playbook -i $K/inventories/k3s.yml $K/cluster.yml
export KUBECONFIG=$PWD/$K/kubeconfig
kubectl get nodes -o wide

ansible-playbook -i localhost, $K/application.yml
ansible-playbook -i localhost, $K/maintenance.yml
```

## Le point critique du TP

Sous VirtualBox, `eth0` est l'interface NAT et porte **10.0.2.15 sur les trois VMs**. Sans
configuration explicite, k3s en déduit son adresse : les nœuds s'enregistrent tous avec la même,
le cluster paraît fonctionner, et le réseau des pods échoue silencieusement.

Le rôle traite ce point en trois temps :

1. l'adresse du nœud vient d'`ansible_host`, pas de `ansible_default_ipv4` ;
2. l'interface est **recherchée** parmi les facts, jamais codée en dur ;
3. une assertion échoue explicitement si aucune interface ne porte cette adresse.

`application.yml` ajoute un filet de sécurité : il vérifie par assertion que les adresses
internes des nœuds sont bien distinctes.

```
kubectl get nodes -o wide
NAME         STATUS   INTERNAL-IP      ...
k3s-master   Ready    192.168.56.41
k3s-node01   Ready    192.168.56.42
k3s-node02   Ready    192.168.56.43
```

Trois adresses identiques, ou en 10.0.2.15, signalent que `node-ip` n'a pas été appliqué.

## Ce que le corrigé illustre

| Point | Emplacement |
|---|---|
| Détection d'interface par les facts | `roles/k3s/tasks/main.yml` |
| Configuration par fichier plutôt que par variables | `templates/config.yaml.j2` |
| Installation idempotente d'un script | `creates: /usr/local/bin/k3s` |
| Rôle serveur ou agent selon le groupe | `'k3s_server' in group_names` |
| Jeton poussé, non lu depuis le serveur | `k3s_token` en défaut de rôle |
| Kubeconfig exploitable depuis le poste | `replace('127.0.0.1', ansible_host)` |
| Manifestes paramétrés | `template:` du module `k8s` |
| Attente d'un état réel | `wait_condition` |
| Opérations de jour 2 | `k8s_drain` |

## Versions

| Élément | Valeur |
|---|---|
| k3s | `v1.36.4+k3s1` (Kubernetes 1.36) |
| `kubernetes.core` | 6.5+ (Helm 4 supporté depuis 6.4) |
| Client Python | `kubernetes >= 24.2.0`, `jsonpatch` |

> À valider sur la machine Ubuntu : le cluster n'a pas pu être monté lors de la rédaction.
> L'ensemble passe `--syntax-check` et `ansible-lint` au profil production.
