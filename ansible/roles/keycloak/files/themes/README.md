# Thèmes Keycloak

Déployés dans `/opt/keycloak/themes` par le rôle, montés en lecture seule dans
le conteneur. Les thèmes fournis par Keycloak (`base`, `keycloak`,
`keycloak.v2`) vivent dans ses JAR et ne sont pas masqués par ce montage.

## odyssai

Ce dossier fait foi. Le thème a d'abord vécu dans `infra/keycloak/themes` du
dépôt odyssai, d'où il était resynchronisé ; il en a été retiré pour que le
rôle reste autonome, une reconstruction du serveur ne devant dépendre d'aucun
autre dépôt présent sur le poste. Son CSS reprend les tokens de l'UI kit
(`apps/web/odyssai-ui-kit.html`), à reporter à la main quand ils bougent.

`parent=base` : seules les pages qui s'écartent de l'original sont surchargées,
les autres héritent des gabarits nus et prennent leur mise en forme des classes
déclarées dans `theme.properties`. Une page surchargée est une copie de celle
de `base` : la rapprocher de l'original à chaque montée de version de Keycloak.
La version en service se lit dans `defaults/main.yml`, et ses gabarits
s'extraient de l'image :

```bash
cid=$(docker create quay.io/keycloak/keycloak:26.7)
docker cp "$cid:/opt/keycloak/lib/lib/main/org.keycloak.keycloak-themes-26.7.3.jar" /tmp/themes.jar
docker rm -f "$cid"
unzip -q -o /tmp/themes.jar 'theme/base/login/*' -d /tmp/kc
```

Après une évolution, rejouer le rôle :

```bash
ansible-playbook ansible/site.yml --tags keycloak
```
