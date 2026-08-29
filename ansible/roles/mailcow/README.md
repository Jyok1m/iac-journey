# Role `mailcow`

mailcow-dockerized behind Traefik, with the Cloudflare DNS the mail setup needs
driven through this repo's own Terraform, and OIDC on the web UI against
Keycloak.

    make mail                       # everything
    make mail TAGS=mailcow-dns      # just the DNS passes
    make mail CHECK=1               # dry run

The reference implementation is the official documentation at
<https://docs.mailcow.email>. Every place this role departs from it is listed
at the bottom with the reason. Anything not listed there is upstream's design,
not ours.

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
rather than only the second. That detail is load-bearing. `mail_dkim_txt` and
`mail_mta_sts_enabled` both default to "absent" in the HCL, so a pass that
omitted them once mailcow was running would plan to **delete** a live DKIM
record — a destructive plan, which the guardrail then refuses, killing the run
on its second execution. Recomputing every time means a steady-state run plans
nothing at all.

## The Terraform boundary

Terraform runs on the control node, never on the mail host: the R2 state
credentials and the Cloudflare token live there and are never copied. Every
pass goes through `terraform_apply.yml`, which captures a plan, reads it back
as JSON, refuses anything containing a `delete`, and only then applies that
exact saved plan file. Nothing is ever auto-approved unread.

Mail records live in `cloudflare_dns_record.mail`, a separate resource from the
pre-existing `cloudflare_dns_record.this`. They share nothing but the provider,
so no change here can put the apex and wildcard records of three zones inside
its blast radius.

## What is not automated, and why

Two things, both because no credential in this repo can reach them:

| Action | Where | Why it cannot be automated |
| --- | --- | --- |
| PTR / rDNS for both addresses → `mail.joachimjasmin.com` | OVH manager | Reverse DNS is delegated to whoever owns the IP block. The role fails with the exact click path if it is wrong. |
| DS record | Squarespace Domains | The zone is on Cloudflare but registered at Squarespace, which has no API credential here. `terraform output mail_dnssec_ds` prints the exact value. |

## Deviations from the official documentation

**CONF-1 — `mailcow.conf` is templated, `generate_config.sh` is never run.**
The script is interactive, it overwrites rather than merges, and its IPv6 step
offers to rewrite `/etc/docker/daemon.json` and restart the Docker daemon —
which on this host would bounce nine unrelated stacks. Templating it also makes
the four values it randomises (`DBPASS`, `DBROOT`, `REDISPASS`,
`SOGO_URL_ENCRYPTION_KEY`) come from ansible-vault, so a rebuild reaches the
same state instead of a new one. Every variable the script would have written
is present in the template.

**TLS-1 — the Postfix cipher list is overridden, but not with upstream's own
recipe.** mailcow's defaults fail internet.nl: `smtpd_tls_ciphers` is unset and
falls back to Postfix's `medium`, whose exclusion list removes fixed DH but not
static-RSA key exchange, so port 25 still offers `AES256-GCM-SHA384` and
SHA-1-MAC suites — graded "insufficient", a zero rather than a warning. The
hardening recipe in mailcow's docs fixes that but writes
`smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1`, and the postfix
container's entrypoint greps for exactly that shape; on a match it appends
`CipherString = DEFAULT@SECLEVEL=0` to `/etc/ssl/openssl.cnf` for the whole
container, re-permitting SHA-1 in TLS 1.2 signature algorithms. `extra.cf` here
uses the `>=TLSv1.2` form, which expresses the same policy without matching
that grep.

**SPF-1 — SPF authorises by literal address, not `v=spf1 mx a -all`.** The
documented example includes `a`, which resolves the apex. The apex here is
Cloudflare-proxied, so `a` would authorise every Cloudflare edge address to
send as this domain. The IPv6 term covers the routed `/64` rather than the
single configured address, because Docker's NAT66 source selection is not
pinned to it.

**CERT-1 — `SKIP_LETS_ENCRYPT=y`; Traefik is the only ACME client.** This is
the external-certificate path upstream documents ("use any external ACME
client… copied to the correct location and a post-hook reloads affected
containers"). The post-hook is a systemd `.path` unit watching Traefik's
`acme.json`, so a renewal happening between Ansible runs still reaches Postfix
and Dovecot. Upstream's own Traefik page was not followed as written: it is
marked community-supported and its container names use Compose v1 naming
(`mailcow_postfix-mailcow_1`) against a project that produces
`mailcowdockerized-postfix-mailcow-1`.

**IPV6-1 — `ENABLE_IPV6=false` inside mailcow's bridge.** Turning it on
requires `/etc/docker/daemon.json` and a daemon restart, which would bounce
every other stack. Inbound IPv6 to the published ports works anyway —
docker-proxy listens on `[::]` regardless — and that is what internet.nl's
reachability subtest measures. The cost is that Postfix sees the bridge gateway
rather than the real source address for IPv6 connections. Revisit once the IPv6
PTR exists.

**SSO-1 — Keycloak covers the web UI, and that is all it can cover.** Mode
`keycloak` rather than `generic-oidc`: mailcow's `user_login()` switches on
`authsource` with cases for `keycloak`, `ldap` and `mailcow` only, so a mailbox
marked `generic-oidc` matches nothing and falls through to `return false`.

IMAP and SMTP **do not** go through Keycloak and cannot today. Dovecot in
mailcow advertises `auth_mechanisms = plain login` and nothing else — no
OAUTHBEARER, no XOAUTH2 — and Postfix delegates SASL to that same passdb.
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

## DANE is not published

`var.mail_tlsa` exists and renders correctly, but nothing fills it in. A
`3 1 1` record pins the certificate's public key, and the certificate
currently comes from Traefik, whose ACME client generates a fresh key on every
renewal — mailcow's own client reuses its key, Traefik's does not. Publishing
a TLSA against a rotating key means DANE-checking senders hard-fail delivery
at the first renewal, which is a worse outcome than the missing subtest.
Closing this means moving the SMTP certificate to a client that reuses its
key; until then internet.nl's DANE subtests are the known gap.
