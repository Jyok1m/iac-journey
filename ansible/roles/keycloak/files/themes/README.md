# Thèmes Keycloak

Déployés dans `/opt/keycloak/themes` par le rôle, montés en lecture seule dans
le conteneur. Les thèmes fournis par Keycloak (`base`, `keycloak`,
`keycloak.v2`) vivent dans ses JAR et ne sont pas masqués par ce montage.

## odyssai

Copie de travail. La source est `infra/keycloak/themes/odyssai` dans le dépôt
odyssai, où elle est testée et où vit l'UI kit dont son CSS reprend les tokens.
Elle est dupliquée ici pour que le rôle reste autonome : une reconstruction du
serveur ne doit dépendre d'aucun autre dépôt présent sur le poste.

Resynchroniser après une évolution du thème, puis rejouer le rôle :

```bash
rsync -a --delete ~/Code/odyssai/infra/keycloak/themes/odyssai/ \
  ansible/roles/keycloak/files/themes/odyssai/
ansible-playbook ansible/site.yml --tags keycloak
```
