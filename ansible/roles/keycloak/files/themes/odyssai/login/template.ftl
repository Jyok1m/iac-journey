<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false displayWide=false showAnotherWayIfPresent=true>
<!DOCTYPE html>
<html class="${properties.kcHtmlClass!}"<#if realm.internationalizationEnabled> lang="${locale.currentLanguageTag}"</#if>>

<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <#-- Theme sombre unique, comme apps/web : pas de variante claire. -->
  <meta name="color-scheme" content="dark">
  <title>${msg("loginTitle",(realm.displayName!''))}</title>
  <link rel="icon" href="${url.resourcesPath}/img/odyssai-mark.svg" type="image/svg+xml">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;500;600&family=Literata:opsz,wght@7..72,400..700&display=swap">
  <#if properties.styles?has_content>
    <#list properties.styles?split(' ') as style>
      <link href="${url.resourcesPath}/${style}" rel="stylesheet">
    </#list>
  </#if>
  <#if properties.scripts?has_content>
    <#list properties.scripts?split(' ') as script>
      <script src="${url.resourcesPath}/${script}" type="text/javascript"></script>
    </#list>
  </#if>
  <#if scripts??>
    <#list scripts as script>
      <script src="${script}" type="text/javascript"></script>
    </#list>
  </#if>
</head>

<body class="${properties.kcBodyClass!} ${bodyClass}">
<div class="odyssai-split">

  <main class="odyssai-pane">
    <div class="odyssai-content">

      <#if realm.internationalizationEnabled && locale.supported?size gt 1>
        <nav class="${properties.kcLocaleClass!}" aria-label="${msg("languages")}">
          <ul class="${properties.kcLocaleListClass!}">
            <#list locale.supported as l>
              <li class="${properties.kcLocaleListItemClass!}">
                <a class="${properties.kcLocaleItemClass!}"<#if l.languageTag == locale.currentLanguageTag> aria-current="true"</#if>
                   href="${l.url}">${l.label}</a>
              </li>
            </#list>
          </ul>
        </nav>
      </#if>

      <#-- Le wordmark ne s'emploie jamais sans le symbole : c'est le lockup
           complet qui est servi ici, jamais le seul texte. -->
      <div class="odyssai-brand">
        <img src="${url.resourcesPath}/img/odyssai-logo-dark.svg" alt="OdyssAI" height="32">
      </div>

      <header class="${properties.kcFormHeaderClass!}">
        <h1 class="odyssai-title"><#nested "header"></h1>
        <#nested "subhead">
        <#if displayRequiredFields>
          <p class="odyssai-required-note"><span class="odyssai-required">*</span> ${msg("requiredFields")}</p>
        </#if>
      </header>

      <#if displayMessage && message?? && message.summary?has_content>
        <div class="${properties.kcAlertClass!} odyssai-alert--${message.type}" role="alert">
          <span class="${properties.kcAlertTitleClass!}">${kcSanitize(message.summary)?no_esc}</span>
        </div>
      </#if>

      <#nested "form">

      <#if auth?has_content && auth.showTryAnotherWayLink() && showAnotherWayIfPresent>
        <form id="kc-select-try-another-way-form" action="${url.loginAction}" method="post">
          <input type="hidden" name="tryAnotherWay" value="on">
          <button type="submit" class="odyssai-linkbutton" id="try-another-way">${msg("doTryAnotherWay")}</button>
        </form>
      </#if>

      <#nested "socialProviders">

      <#if displayInfo>
        <div class="${properties.kcInfoAreaClass!}">
          <#nested "info">
        </div>
      </#if>

    </div>
  </main>

  <#-- Panneau d'ambiance. Purement decoratif et sans requete reseau : un
       lecteur d'ecran n'a rien a y lire. -->
  <aside class="odyssai-cover" aria-hidden="true">
    <div class="odyssai-cover-sky">
      <svg class="odyssai-portal" viewBox="0 0 240 260" role="presentation" focusable="false">
        <defs>
          <radialGradient id="halo" cx="50%" cy="42%" r="58%">
            <stop offset="0%" stop-color="var(--accent)" stop-opacity=".55"/>
            <stop offset="60%" stop-color="var(--accent)" stop-opacity=".10"/>
            <stop offset="100%" stop-color="var(--accent)" stop-opacity="0"/>
          </radialGradient>
        </defs>
        <rect x="0" y="0" width="240" height="260" fill="url(#halo)"/>
        <path d="M20 250 V120 A100 100 0 0 1 220 120 V250 Z"
              fill="none" stroke="var(--accent)" stroke-opacity=".5" stroke-width="1.5"/>
        <path d="M52 250 V126 A68 68 0 0 1 188 126 V250 Z"
              fill="none" stroke="var(--accent)" stroke-opacity=".28" stroke-width="1"/>
        <circle cx="120" cy="120" r="3" fill="var(--accent)"/>
        <circle cx="66" cy="72" r="1.6" fill="#ede6d6" fill-opacity=".7"/>
        <circle cx="176" cy="54" r="1.2" fill="#ede6d6" fill-opacity=".5"/>
        <circle cx="205" cy="96" r="1.8" fill="#d4a84f" fill-opacity=".65"/>
        <circle cx="36" cy="150" r="1.3" fill="#9d8cf2" fill-opacity=".6"/>
      </svg>
    </div>
    <blockquote class="odyssai-cover-quote">
      <p>Chaque joueur ouvre son univers. Certains se croisent.</p>
    </blockquote>
  </aside>

</div>
</body>
</html>
</#macro>
