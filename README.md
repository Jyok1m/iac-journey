# iac-journey

Infrastructure du serveur portfolio : DNS Cloudflare géré par Terraform, stacks
Docker déployées par Ansible sur un serveur OVH unique (`main`, groupe
`portfolio`).

## Stacks déployées

| Rôle       | Contenu                                     | URL                       |
| ---------- | ------------------------------------------- | ------------------------- |
| `keycloak` | Keycloak + PostgreSQL                       | `sso.<domaine>`           |
| `komodo`   | Komodo Core + Periphery + MongoDB           | `komodo.<domaine>`        |
| `heirloom` | API + app + site vitrine + PostgreSQL       | `heirloom*.<domaine>`     |

## Prérequis

- Terraform ≥ 1.15, `ansible-core` ≥ 2.21, `pre-commit`
- Collections Ansible : `ansible-galaxy collection install -r ansible/requirements.yml`
- Hooks Git : `pre-commit install`
- Mot de passe vault dans `~/.ansible/vault-pass-iac-journey` (chemin fixé par
  `ansible.cfg`, hors du repo)
- Clé SSH `~/.ssh/portfolio/id_ed25519_ovh-server`
- `terraform/backend.hcl` et `terraform/terraform.tfvars` (voir les `.example`)

## Ordre d'exécution

Terraform d'abord — les rôles Ansible génèrent des routeurs Traefik qui
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
ansible-playbook ansible/site.yml --tags system-apps    # keycloak + komodo
ansible-playbook ansible/site.yml --tags personal-apps  # heirloom
```

## Dépendances hors repo

À connaître avant de croire que `site.yml` reconstruit une machine vierge — il
ne le fait pas. Sont supposés déjà en place sur l'hôte :

- Docker Engine + plugin Compose
- Traefik, avec l'entrypoint `websecure` et le certresolver `letsencrypt`
- le réseau Docker `traefik-public` (déclaré `external: true` dans les stacks)
- le durcissement système (firewall, SSH, mises à jour automatiques)

## Secrets

Les secrets vivent dans des fichiers Ansible Vault, jamais en clair :

- `ansible/vaults/<rôle>.yml` — chargés par `vars_files` dans le play concerné
- `ansible/host_vars/main/vault.yml` — connexion SSH (`ansible_host`, `ansible_port`)

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
garde-fou — il ne protège rien si les hooks ne sont pas installés
(`pre-commit install`) ou si un commit passe en `--no-verify`.

```bash
pre-commit run --all-files                          # gitleaks, ansible-lint, vaults
cd terraform && terraform fmt -check -recursive && terraform validate
```

À savoir si la question d'une CI revient : `ansible-lint` a besoin du fichier
pointé par `vault_password_file` dans `ansible.cfg`, sinon il échoue au
chargement de la config. Et son `--syntax-check` déchiffre réellement les
`vars_files` de `site.yml` — linter le playbook complet ailleurs qu'en local
suppose donc d'exposer le mot de passe du vault.
