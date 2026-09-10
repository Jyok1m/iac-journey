<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('username','password') displayInfo=false; section>

  <#if section = "header">
    ${msg("loginAccountTitle")}

  <#elseif section = "subhead">
    <#-- Dans la maquette le renvoi vers l'inscription est sous le titre, pas
         en pied de formulaire : d'ou cette section plutot que "info". -->
    <#if realm.password && realm.registrationAllowed && !registrationDisabled??>
      <p class="odyssai-lede">
        ${msg("noAccount")}
        <a href="${url.registrationUrl}">${msg("doRegister")}</a>
      </p>
    </#if>

  <#elseif section = "form">
    <#if realm.password>
      <form id="kc-form-login" class="${properties.kcFormClass!}" action="${url.loginAction}" method="post"
            novalidate>

        <div class="${properties.kcFormGroupClass!}<#if messagesPerField.existsError('username','password')> ${properties.kcFormGroupErrorClass!}</#if>">
          <label for="username" class="${properties.kcLabelClass!}">
            <#if !realm.loginWithEmailAllowed>${msg("username")}
            <#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}
            <#else>${msg("email")}</#if>
          </label>
          <input id="username" name="username" class="${properties.kcInputClass!}"
                 type="<#if realm.loginWithEmailAllowed && realm.registrationEmailAsUsername>email<#else>text</#if>"
                 value="${(login.username!'')}"
                 autocomplete="<#if realm.registrationEmailAsUsername>email<#else>username</#if>"
                 autofocus
                 required
                 aria-invalid="<#if messagesPerField.existsError('username','password')>true</#if>"
                 <#if usernameEditDisabled??>disabled</#if>>

          <#if messagesPerField.existsError('username','password')>
            <span id="input-error" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
              ${kcSanitize(messagesPerField.getFirstError('username','password'))?no_esc}
            </span>
          </#if>
        </div>

        <div class="${properties.kcFormGroupClass!}">
          <label for="password" class="${properties.kcLabelClass!}">${msg("password")}</label>
          <input id="password" name="password" class="${properties.kcInputClass!}" type="password"
                 autocomplete="current-password"
                 required
                 aria-invalid="<#if messagesPerField.existsError('username','password')>true</#if>">
        </div>

        <div class="${properties.kcFormOptionsClass!}">
          <#if realm.rememberMe && !usernameEditDisabled??>
            <label class="odyssai-remember">
              <input id="rememberMe" name="rememberMe" type="checkbox"
                     class="${properties.kcCheckboxInputClass!}"
                     <#if login.rememberMe??>checked</#if>>
              <span>${msg("rememberMe")}</span>
            </label>
          <#else>
            <span></span>
          </#if>

          <#if realm.resetPasswordAllowed>
            <a class="odyssai-forgot" href="${url.loginResetCredentialsUrl}">${msg("doForgotPassword")}</a>
          </#if>
        </div>

        <div class="${properties.kcFormButtonsClass!}">
          <#-- Jeton anti-rejeu du flot d'authentification, pose par Keycloak. -->
          <input type="hidden" id="id-hidden-input" name="credentialId"
                 value="<#if auth.selectedCredential?has_content>${auth.selectedCredential}</#if>">
          <button type="submit" name="login" id="kc-login"
                  class="${properties.kcButtonClass!} ${properties.kcButtonPrimaryClass!} ${properties.kcButtonBlockClass!}"
                  <#if usernameEditDisabled??>disabled</#if>>${msg("doLogIn")}</button>
        </div>
      </form>
    </#if>

  <#elseif section = "socialProviders">
    <#-- La section n'apparait que si le realm declare des fournisseurs :
         pas de bouton Google ou GitHub qui ne menerait nulle part. -->
    <#if realm.password && social?? && social.providers?? && social.providers?has_content>
      <div class="${properties.kcFormSocialAccountSectionClass!}">
        <div class="odyssai-separator"><span>${msg("identity-provider-login-label")}</span></div>
        <ul class="${properties.kcFormSocialAccountListClass!}<#if social.providers?size gt 1> ${properties.kcFormSocialAccountListGridClass!}</#if>">
          <#list social.providers as p>
            <li>
              <a id="social-${p.alias}" class="${properties.kcFormSocialAccountListButtonClass!}"
                 href="${p.loginUrl}">
                <#if p.iconClasses?has_content><i class="${p.iconClasses!}" aria-hidden="true"></i></#if>
                <span class="${properties.kcFormSocialAccountNameClass!}">${p.displayName!}</span>
              </a>
            </li>
          </#list>
        </ul>
      </div>
    </#if>
  </#if>

</@layout.registrationLayout>
