<#--
  Exigences de la politique de mot de passe du realm.

  Keycloak n'expose pas passwordPolicy au gabarit : seule la politique du TOTP
  l'est, par totp.policy. Le texte vit donc dans les messages du theme et doit
  suivre le passwordPolicy pose par files/setup-realm.sh. Les deux changent
  ensemble, sans quoi l'ecran annonce une regle que le serveur n'applique pas.
-->
<#macro requirements>
    <div class="odyssai-requirements">
        <p class="odyssai-requirements-title">${msg("passwordRequirementsTitle")}</p>
        <ul>
            <li>${msg("passwordRequirementsLength")}</li>
            <li>${msg("passwordRequirementsNotIdentity")}</li>
            <li>${msg("passwordRequirementsHistory")}</li>
        </ul>
    </div>
</#macro>
