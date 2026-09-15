# iac-journey

Infrastructure Ansible + Terraform d'un serveur OVH unique. Le README décrit
l'architecture et l'ordre de déploiement ; ce fichier ne couvre que les
conventions d'écriture, qui priment sur les habitudes par défaut.

## Commits

- **Jamais de trailer `Co-Authored-By`**, ni de mention d'un outil de
  génération, ni d'emoji de pied de message. L'historique n'a qu'un auteur.
- Conventional commits, en français **sans accents** :
  `feat(odyssai): une base postgres par copie de la stack`.
- Le corps explique le pourquoi et le piège évité, pas le diff. Un lecteur qui
  a le diff sous les yeux n'a pas besoin qu'on le lui raconte.
- Historique linéaire sur `main`, pas de merge, pas de branche par changement.

## Écriture

**Aucun tiret cadratin (`—`) ni demi-cadratin (`–`), nulle part** : code,
commentaires, messages de commit, Markdown, chaînes de caractères, valeurs de
configuration. Selon ce que la phrase demande, remplacer par :

| Remplacement   | Quand                                             |
| -------------- | ------------------------------------------------- |
| `:`            | ce qui suit explique ce qui précède               |
| `,`            | simple coordination                               |
| `( )`          | incise, notamment un double tiret qui l'encadrait |
| `.`            | la phrase est trop longue et gagne à être coupée  |

Si aucun ne tient, reformuler la phrase plutôt que de forcer la ponctuation.

Un fichier est soit en français soit en anglais, jamais les deux. Suivre la
langue déjà en place dans le fichier ; les rôles existants sont majoritairement
en anglais, le README et le rôle `keycloak` en français.

## Commentaires

Rares et courts. Un commentaire existe pour le piège qui coûte une soirée à
retrouver, jamais pour reformuler la ligne suivante.

À supprimer :

- les bannières de section en ASCII ;
- les libellés qui répètent le nom de la variable (`# Service Postgres`
  au-dessus de `foo_pg_image`) ;
- toute phrase qui paraphrase ce que le code dit déjà.

À garder, en une ou deux lignes :

- le comportement non évident d'un outil tiers (`postfix.sh` qui réécrit
  `main.cf` à chaque démarrage, Compose qui estampille ses réseaux) ;
- la contrainte externe qui a dicté une valeur (pool d'adresses Docker,
  protection anti-robot de Cloudflare, taille des chaînes TXT) ;
- la raison d'un choix contre-intuitif.

Le même piège ne se commente qu'une fois. S'il concerne plusieurs fichiers, une
ligne dans le premier suffit.

## Vérifications avant de commiter

```bash
pre-commit run --all-files
cd terraform && terraform fmt -check -recursive && terraform validate
```

`ansible-lint` tourne en hook et doit rester à 0 failure sur le profil
`production`. Il lui faut le fichier pointé par `vault_password_file` dans
`ansible.cfg`, donc il ne tourne qu'en local.

Pour valider un template de compose sans déployer : rendre le Jinja avec les
defaults du rôle dans un fichier temporaire, puis
`docker compose -f <rendu> config --quiet`.

## Secrets

- Tout secret vit dans un fichier Ansible Vault chiffré, jamais en clair. Le
  hook `check-vault-encrypted` refuse le commit d'un vault déchiffré.
- Les variables de vault sont **préfixées par le rôle**
  (`odyssai_vault_pg_password`) : `host_vars/` a une précédence supérieure aux
  `vars_files` d'un play, donc une clé non préfixée écraserait silencieusement
  celle de tous les rôles.
- Éditer avec `ansible-vault edit`, qui rechiffre à la sauvegarde. `make
  decrypt` et `make encrypt` pour un passage en clair temporaire.
- Un secret ne va jamais dans un `docker-compose.yml` : il passe par un
  `env_file` rendu en 0640, sinon `docker inspect` le rend lisible à tout le
  groupe de déploiement.

## Docker

Un port publié depuis un réseau déclaré `internal: true` n'est joignable par
rien. Le conteneur doit aussi rejoindre un bridge ordinaire, à la manière de
`odyssai-db-host` et de `ipseis-db-host`.

Les images tierces sont épinglées par digest. Les clés de réseaux et de volumes
d'un compose sont figées pour la vie de la stack : Compose refuse d'adopter une
ressource dont le label `com.docker.compose.*` ne correspond plus.
