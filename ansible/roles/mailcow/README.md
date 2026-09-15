# Role `mailcow`

mailcow-dockerized behind Traefik, with the Cloudflare DNS the mail setup needs
driven through this repo's own Terraform, and OIDC on the web UI against
Keycloak. One host, several domains.

    make mail                       # everything
    make mail TAGS=mailcow-dns      # just the DNS passes
    make mail CHECK=1               # dry run

The reference implementation is the official documentation at
<https://docs.mailcow.email>. Every place this role departs from it is listed
at the bottom with the reason. Anything not listed there is upstream's design,
not ours.

## One host, several sending domains

`mail.joachimjasmin.com` is the only hostname. It is the SMTP HELO name, the
PTR target and the CN of the certificate on 25/465/587, and those three have to
agree, so it belongs to the machine, not to any one domain. Adding a domain
adds no hostname, no address, no certificate and no reverse record.

What is per-domain is everything a receiver checks against the envelope
sender (MX, SPF, DKIM, DMARC, TLS-RPT, MTA-STS), plus the domain and its
mailboxes inside mailcow.

| Domain | Mailboxes | Client autoconfig |
| --- | --- | --- |
| `joachimjasmin.com` | info, invoice, dmarc, newsletter, no-reply, alert | yes |
| `ipseis.eu` | helenedm | yes |
| `odyssai.app` | no-reply | no |

Each address is an ordinary mailbox with its own password, so every app
authenticates on submission as itself: a leaked password sends as one address,
not as the domain. Passwords live in `mailcow_vault_mailboxes`, **keyed by the
full address** : `no-reply` exists on two of these domains, and a map keyed on
the local part alone would have silently given them one shared password.

`client_autoconfig` is off for `odyssai.app` because nothing there is ever
opened in a mail client. It publishes `autodiscover`/`autoconfig`, eleven SRV
records and two DAV hints, and each of those two names becomes a certificate
Traefik has to keep renewing. `mta_sts` is a separate switch and stays on
everywhere: that one is about how other MTAs deliver to us.

The domain list is written down twice (`mailcow_domains` in this role,
`mail_domains` in `terraform/mail.auto.tfvars`) because there is no file a
tfvars and an Ansible role can both read. Preflight compares them and refuses
to run if they disagree. A domain in one and not the other fails in a way that
looks like a working deployment: mailboxes whose mail has no MX, or an MX for
a domain mailcow rejects at RCPT TO, which turns this host into a backscatter
source.

### DMARC reports cross a domain boundary here

All three domains send their aggregate reports to `dmarc@joachimjasmin.com`.
RFC 7489 §7.1 makes that conditional: a receiver must not send reports to a
mailbox outside the domain the DMARC record belongs to unless that other domain
publishes `"v=DMARC1"` at `<policy-domain>._report._dmarc.<report-domain>`.
`mail.tf` derives those records and publishes them into the report domain's
zone. Without them the reports are simply never sent, and `p=reject` is
enforced with nobody watching. TLS-RPT has no equivalent requirement (RFC 8460
§3), so nothing is published for it.

## Why the DNS is applied in two passes

The ordering is the actual problem this role solves, and it is not a straight
line:

- ACME cannot issue a certificate for a name that does not resolve yet, so the
  A record has to exist and have propagated *before* the stack comes up.
- The DKIM key does not exist until mailcow is running and the domain has been
  created inside it, so that record cannot be part of the first pass.
- OVH refuses a reverse record whose forward record does not already point at
  the address, so the PTR check has to sit between the two.

So: `dns_base` publishes everything knowable up front and blocks on a public
resolver returning it; `ptr` refuses to continue if the reverse is wrong;
`dkim` runs after the stack is up and publishes what mailcow generated.

`tf_vars.yml` recomputes the dynamic Terraform inputs before *both* passes
rather than only the second. That detail is load-bearing. `mail_dkim` and
`mail_mta_sts_serving` both default to "absent" in the HCL, so a pass that
omitted them once mailcow was running would plan to **delete** a live DKIM
record, a destructive plan, which the guardrail then refuses, killing the run
on its second execution. Recomputing every time means a steady-state run plans
nothing at all.

Both are maps keyed by domain, and a domain missing from either keeps its own
record out of the plan without touching the others. That is what lets a fourth
domain be added later: its DKIM record appears on the pass after mailcow
generates the key, while the three that already work stay untouched.

The corollary is that the generated file must never be rewritten from an
unanswered question. It is not a report of what mailcow says right now; it is
the last state terraform was told to publish. On the first pass of any deploy
the stack is down: that pass is what publishes the DNS the stack needs to come
up, so the API returns nothing, and writing that through as an empty map plans
to **delete** a live DKIM record. The guardrail refuses it, correctly, and the
run dies before it can bring anything up. `tf_vars.yml` therefore only rewrites
the file when every domain actually answered. "This domain has no key" (HTTP
200, empty `dkim_txt`) is an answer and is written through; "mailcow did not
answer" is not, and leaves the file alone.

## The Terraform boundary

Terraform runs on the control node, never on the mail host: the R2 state
credentials and the Cloudflare token live there and are never copied. Every
pass goes through `terraform_apply.yml`, which captures a plan, reads it back
as JSON, refuses anything containing a `delete`, and only then applies that
exact saved plan file. Nothing is ever auto-approved unread.

Mail records live in `cloudflare_dns_record.mail`, a separate resource from the
pre-existing `cloudflare_dns_record.this`. They share nothing but the provider,
so no change here can put the apex and wildcard records of five zones inside
its blast radius.

Going multi-domain moved every key of that resource from `<slot>` to
`<domain>/<slot>`, which Terraform reads as delete-then-create. `mail.moved.tf`
states the rename instead. Those blocks are no-ops once the state has moved and
are kept rather than deleted: without them, a restored older state would plan
to tear down and rebuild the live MX, SPF and DKIM of a working mail server,
and the guardrail would (correctly) abort the run instead.

## What is not automated, and why

Two things, both because no credential in this repo can reach them:

| Action | Where | Why it cannot be automated |
| --- | --- | --- |
| PTR / rDNS for both addresses → `mail.joachimjasmin.com` | OVH manager | Reverse DNS is delegated to whoever owns the IP block. The role fails with the exact click path if it is wrong. One PTR covers every domain, the hostname is shared. |
| DS records | each zone's registrar | The zones are on Cloudflare but registered elsewhere, and the three are registered in three different places. `terraform output mail_dnssec_ds` prints the value for each signed zone. |

Only `joachimjasmin.com` is listed in `mail_dnssec_domains` today. Signing the
other two at Cloudflare is free and reversible, but the chain of trust only
closes once each DS is pasted at its own registrar, so they are left out until
someone is ready to do that. `terraform output mail_dnssec_status` tells a zone
that is not being signed at all (`disabled`) apart from one that is signed and
waiting on its registrar (`pending`).

## Deviations from the official documentation

**CONF-1 : `mailcow.conf` is templated, `generate_config.sh` is never run.**
The script is interactive, it overwrites rather than merges, and its IPv6 step
offers to rewrite `/etc/docker/daemon.json` and restart the Docker daemon,
which on this host would bounce nine unrelated stacks. Templating it also makes
the four values it randomises (`DBPASS`, `DBROOT`, `REDISPASS`,
`SOGO_URL_ENCRYPTION_KEY`) come from ansible-vault, so a rebuild reaches the
same state instead of a new one. Every variable the script would have written
is present in the template.

**TLS-1 : the Postfix cipher list is overridden, but not with upstream's own
recipe.** mailcow's defaults fail internet.nl: `smtpd_tls_ciphers` is unset and
falls back to Postfix's `medium`, whose exclusion list removes fixed DH but not
static-RSA key exchange, so port 25 still offers `AES256-GCM-SHA384` and
SHA-1-MAC suites, graded "insufficient", a zero rather than a warning. The
hardening recipe in mailcow's docs fixes that but writes
`smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1`, and the postfix
container's entrypoint greps for exactly that shape; on a match it appends
`CipherString = DEFAULT@SECLEVEL=0` to `/etc/ssl/openssl.cnf` for the whole
container, re-permitting SHA-1 in TLS 1.2 signature algorithms. `extra.cf` here
uses the `>=TLSv1.2` form, which expresses the same policy without matching
that grep.

**SPF-1 : SPF authorises by literal address, not `v=spf1 mx a -all`.** The
documented example includes `a`, which resolves the apex. The apex here is
Cloudflare-proxied, so `a` would authorise every Cloudflare edge address to
send as this domain. The IPv6 term covers the routed `/64` rather than the
single configured address, because Docker's NAT66 source selection is not
pinned to it.

**CERT-1 : `SKIP_LETS_ENCRYPT=y`; Traefik is the only ACME client.** This is
the external-certificate path upstream documents ("use any external ACME
client… copied to the correct location and a post-hook reloads affected
containers"). The post-hook is a systemd `.path` unit watching Traefik's
`acme.json`, so a renewal happening between Ansible runs still reaches Postfix
and Dovecot. Upstream's own Traefik page was not followed as written: it is
marked community-supported and its container names use Compose v1 naming
(`mailcow_postfix-mailcow_1`) against a project that produces
`mailcowdockerized-postfix-mailcow-1`.

**IPV6-1 : `ENABLE_IPV6=false` inside mailcow's bridge.** Turning it on
requires `/etc/docker/daemon.json` and a daemon restart, which would bounce
every other stack. Inbound IPv6 to the published ports works anyway
(docker-proxy listens on `[::]` regardless), and that is what internet.nl's
reachability subtest measures. The cost is that Postfix sees the bridge gateway
rather than the real source address for IPv6 connections. Revisit once the IPv6
PTR exists.

**SSO-1 : Keycloak covers the web UI, and that is all it can cover.** Mode
`keycloak` rather than `generic-oidc`: mailcow's `user_login()` switches on
`authsource` with cases for `keycloak`, `ldap` and `mailcow` only, so a mailbox
marked `generic-oidc` matches nothing and falls through to `return false`.

IMAP and SMTP **do not** go through Keycloak and cannot today. Dovecot in
mailcow advertises `auth_mechanisms = plain login` and nothing else (no
OAUTHBEARER, no XOAUTH2), and Postfix delegates SASL to that same passdb.
mailcow's "mailpassword flow" looks like it closes this gap and does not: it
compares the offered password against a bcrypt hash stored in a Keycloak *user
attribute*, fetched over the Admin REST API. The credential Keycloak holds is
never consulted, and changing a password in Keycloak would not change the mail
password, so it is left off. Mail clients use app passwords.

SOGo has no OIDC in the mailcow build; direct SOGo login has been disabled
upstream since release 2025-03. It is reached by an nginx `auth_request`
against the mailcow session, which injects a master password. The user never
retypes anything, but SOGo never speaks to Keycloak either.

The only mode where a directory credential really validates IMAP and SMTP is
LDAP, and Keycloak consumes LDAP rather than serving it.

## SOGo has to be restarted when a domain is added

SOGo enumerates the mail domains from the database exactly once, in
`bootstrap-sogo.sh` at container start, and writes one `SOGoUserSources` block
per domain into `/etc/sogo/sogo.conf`. Nothing re-reads it afterwards, and
nothing in the stack restarts SOGo when mailcow gains a domain.

The failure this produces is worth naming because it does not look like what it
is. Every mailbox in the new domain authenticates against mailcow perfectly
(the UI log records `logged_in_as` with `Provider: mailcow`), and then the
redirect to the webmail answers **Unauthorized**. IMAP and SMTP keep working
throughout, because Dovecot and Postfix read the database live. So it reads as
a bad password on an account whose password is demonstrably good.

`domain.yml` therefore notifies a `Restart sogo` handler whenever it actually
creates a domain. Creating one by hand in the UI has the same consequence and
no handler behind it:

    cd /opt/mailcow && docker compose restart sogo-mailcow

## MTA-STS is wired up but never announced

`mail_mta_sts_serving` gates the `_mta-sts` TXT on mailcow actually answering
`/.well-known/mta-sts.txt` with a policy. It never does: this build returns 404
on that path for every domain, including one that has been serving mail for
months. So the gate holds and the TXT stays unpublished.

That is the right outcome, not a bug to route around. Announcing `v=STSv1` for
a policy nobody serves makes every sending MTA fetch a 404, fail closed or fall
back depending on its implementation, and file a TLS-RPT failure against us,
strictly worse than not announcing at all.

What is published is the `mta-sts.<domain>` CNAME and its certificate, on all
three domains. They cost three names on Traefik's renewal list and buy the
ability to turn the announcement on in a single run the day upstream serves the
policy. `verify` reports the state and does not fail on it.

## DANE is not published

`var.mail_tlsa` exists and renders correctly, but nothing fills it in. A
`3 1 1` record pins the certificate's public key, and the certificate
currently comes from Traefik, whose ACME client generates a fresh key on every
renewal: mailcow's own client reuses its key, Traefik's does not. Publishing
a TLSA against a rotating key means DANE-checking senders hard-fail delivery
at the first renewal, which is a worse outcome than the missing subtest.
Closing this means moving the SMTP certificate to a client that reuses its
key; until then internet.nl's DANE subtests are the known gap.
