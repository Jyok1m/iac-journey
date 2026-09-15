# iac-journey

Infrastructure du serveur portfolio : DNS Cloudflare géré par Terraform, stacks
Docker déployées par Ansible sur un serveur OVH unique (`main`, groupe
`portfolio`).

## Configuration de l'hôte

| Rôle                | Rôle joué                                             |
| ------------------- | ----------------------------------------------------- |
| `hardening`         | sshd durci, ufw, fail2ban                             |
| `vrack`             | netplan de l'interface vRack (réseau privé OVH)       |
| `docker`            | Docker Engine + plugin Compose v2, depuis le dépôt apt Docker |
| `docker_registries` | `docker login` sur les registres activés              |
| `traefik`           | reverse proxy, TLS Let's Encrypt, réseau `traefik-public` |

## Stacks déployées

| Rôle         | Contenu                                     | URL                     |
| ------------ | ------------------------------------------- | ----------------------- |
| `keycloak`   | Keycloak + PostgreSQL                       | `sso.<domaine>`         |
| `komodo`     | Komodo Core + Periphery + MongoDB           | `komodo.<domaine>`      |
| `jenkins`    | Jenkins + Docker-in-Docker                  | `jenkins.<domaine>`     |
| `monitoring` | Prometheus + Grafana + node-exporter + cAdvisor | `grafana.<domaine>`  |
| `heirloom`   | API + app + site vitrine + PostgreSQL       | `heirloom*.<domaine>`   |
| `portfolio`  | Site personnel                              | apex `.com` et `.fr`    |
| `n8n`        | n8n + PostgreSQL                            | `n8n.<domaine>`         |
| `ipseis`     | API + MongoDB, en prod et en dev            | `ipseis-backend*.<dom>` |

`backup_mongo` est un rôle utilitaire, pas une stack : il installe un timer
systemd qui dump une base Mongo et pousse l'archive dans restic. `ipseis`
l'appelle pour sa base ; il est réutilisable tel quel pour Komodo.

`traefik` doit tourner avant toute stack applicative : c'est lui qui crée le
réseau `traefik-public`, que les autres déclarent en `external: true`. L'ordre
des plays dans `site.yml` le garantit.

## Prérequis

- Terraform ≥ 1.15, `ansible-core` ≥ 2.21, `pre-commit`
- Collections Ansible : `ansible-galaxy collection install -r ansible/requirements.yml`
- Hooks Git : `pre-commit install`
- Mot de passe vault dans `~/.ansible/vault-pass-iac-journey` (chemin fixé par
  `ansible.cfg`, hors du repo)
- Clé SSH `~/.ssh/portfolio/id_ed25519_ovh-server`
- `terraform/backend.hcl` et `terraform/terraform.tfvars` (voir les `.example`)

## Ordre d'exécution

Terraform d'abord : les rôles Ansible génèrent des routeurs Traefik qui
supposent que les enregistrements DNS résolvent déjà, sinon Let's Encrypt
échoue sur le challenge HTTP-01.

```bash
# 1. DNS
cd terraform
terraform init -backend-config=backend.hcl
terraform apply

# 2. Stacks
ansible-playbook ansible/site.yml
```

Cibler une partie du déploiement :

```bash
ansible-playbook ansible/site.yml --tags setup          # hardening, vrack, docker, registres
ansible-playbook ansible/site.yml --tags registries     # relogin sur les registres seuls
ansible-playbook ansible/site.yml --tags edge           # traefik
ansible-playbook ansible/site.yml --tags system-apps    # keycloak, komodo, jenkins, monitoring
ansible-playbook ansible/site.yml --tags personal-apps  # heirloom, portfolio, n8n
ansible-playbook ansible/site.yml --tags client-apps    # ipseis
ansible-playbook ansible/site.yml --tags ipseis         # une seule stack
```

Le tag `setup` est le seul qui peut te couper l'accès : il change le port
d'écoute de sshd et active ufw. `hardening_ssh_port` est dérivé de
`vault_ansible_port`, donc le port que sshd écoute et celui qu'Ansible compose
sont la même variable, mais garde une session ouverte pendant le premier run,
et vérifie que le port est bien dans `hardening_ufw_allowed_ports` avant de
lancer.

## Sauvegardes Mongo

Le rôle `backup_mongo` pose, par instance, un timer `backup-mongo-<nom>.timer`
et deux scripts dans `/usr/local/bin`. Le dump tourne dans un conteneur jetable
raccroché au réseau interne de la stack : la base n'a pas besoin d'être exposée
sur l'hôte pour être sauvegardée.

```bash
systemctl list-timers 'backup-mongo-*'          # prochaine exécution
journalctl -u backup-mongo-ipseis.service       # dernier dump
restic snapshots --tag ipseis                   # ce qui est réellement stocké

# Restauration : --drop écrase les collections existantes
backup-mongo-restore-ipseis.sh latest --drop
```

Les identifiants restic et OVH S3 vivent dans `ansible/vaults/backups.yml`,
séparés des secrets applicatifs parce qu'ils sont partagés entre toutes les
bases sauvegardées.

## Registres Docker

Le rôle `docker_registries` fait le `docker login` sur l'hôte. Trois registres,
chacun activable indépendamment. Les trois sont actifs et cohabitent : Docker
écrit une entrée par registre dans son fichier de config, elles ne s'écrasent
pas.

| Registre   | Variable d'activation                 | URL                           |
| ---------- | ------------------------------------- | ----------------------------- |
| Docker Hub | `docker_registries_dockerhub_enabled` | `https://index.docker.io/v1/` |
| GitLab.com | `docker_registries_gitlab_enabled`    | `registry.gitlab.com`         |
| GitHub     | `docker_registries_github_enabled`    | `ghcr.io`                      |

Les identifiants vivent dans `ansible/vaults/registries.yml`, à éditer avec
`ansible-vault edit` (qui rechiffre à la sauvegarde). Un registre activé sans
identifiant fait échouer le play sur une assertion qui le nomme, avant toute
tentative de connexion, et comme le play `setup` passe en premier, cet échec
arrête tout le reste du déploiement.

Vérifier l'état réel sur l'hôte :

```bash
sudo jq '.auths | keys' /root/.docker/config.json
```

Attention au type de jeton : ghcr.io n'accepte que les PAT GitHub **classiques**,
pas les fine-grained. Côté GitLab, un PAT ou un deploy token convient.

Utilise des jetons, pas des mots de passe de compte : `docker login` écrit dans
`/root/.docker/config.json`, où les identifiants sont encodés en base64 et non
chiffrés. Portées minimales : `read_registry` côté GitLab, `read:packages` côté
GitHub, plus les équivalents en écriture seulement si tu pousses.

## Dépendances hors repo

`site.yml` part maintenant d'une Debian nue : durcissement, réseau vRack,
Docker, authentification aux registres, proxy, puis les stacks. Reste supposé
en place :

- **Mailcow**, dont le firewall ouvre les ports SMTP/IMAP/POP3 sans le déployer

## Secrets

Les secrets vivent dans des fichiers Ansible Vault, jamais en clair :

- `ansible/vaults/<rôle>.yml` : chargés par `vars_files` dans le play concerné
- `ansible/host_vars/main/vault.yml` : connexion SSH (`ansible_host`, `ansible_port`)

Les variables sont **préfixées par le rôle** (`heirloom_vault_db_user`,
`keycloak_vault_db_user`, …). C'est ce qui empêche deux stacks de se marcher
dessus : `host_vars/` a une précédence supérieure aux `vars_files` d'un play,
donc une clé non préfixée qui y atterrirait écraserait silencieusement celle de
tous les rôles.

```bash
make encrypt   # chiffre les vaults en clair
make decrypt   # déchiffre pour édition
```

Trois garde-fous en pre-commit : `gitleaks`, un hook qui refuse tout vault non
chiffré, et un hook qui refuse tout `.env` en clair.

## Vérifications

Pas de CI : les contrôles tournent en local, et pre-commit est donc le seul
garde-fou. Il ne protège rien si les hooks ne sont pas installés
(`pre-commit install`) ou si un commit passe en `--no-verify`.

```bash
pre-commit run --all-files                          # gitleaks, ansible-lint, vaults
cd terraform && terraform fmt -check -recursive && terraform validate
```

À savoir si la question d'une CI revient : `ansible-lint` a besoin du fichier
pointé par `vault_password_file` dans `ansible.cfg`, sinon il échoue au
chargement de la config. Et son `--syntax-check` déchiffre réellement les
`vars_files` de `site.yml`, donc linter le playbook complet ailleurs qu'en local
suppose donc d'exposer le mot de passe du vault.
