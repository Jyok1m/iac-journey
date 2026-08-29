# ------------------------------------------------------------------ #
#                          Mail DNS (mailcow)                        #
# ------------------------------------------------------------------ #
# Deliberately a separate resource from cloudflare_dns_record.this.
# That one owns the apex and the wildcard for all three zones behind a
# for_each keyed on "<zone>/<slot>"; folding mail records into its map
# would put six live, unrelated records inside the blast radius of every
# change made here. A second resource shares nothing but the provider.
#
# Every record below is unproxied. The zone's apex and wildcard are
# proxied, so mail.<domain> resolves to a Cloudflare edge address until an
# explicit record exists for that name — and an MX pointing at the HTTP
# proxy accepts no SMTP. An exact-name record wins over the wildcard
# without modifying it.

locals {
  mail_zone_id = var.zone_ids[var.mail_domain]

  # Client autoconfiguration endpoints, plus the MTA-STS policy host.
  # All three are served over HTTPS by Traefik and so must reach the host
  # directly for ACME — hence CNAMEs onto the unproxied hostname rather
  # than proxied records of their own.
  mail_aliases = ["autodiscover", "autoconfig", "mta-sts"]

  # docs.mailcow.email/getstarted/prerequisite-dns/ — "The advanced DNS
  # configuration". Ports are mailcow's published defaults.
  mail_srv = {
    "_autodiscover._tcp" = { port = 443 }
    "_caldavs._tcp"      = { port = 443 }
    "_carddavs._tcp"     = { port = 443 }
    "_imap._tcp"         = { port = 143 }
    "_imaps._tcp"        = { port = 993 }
    "_pop3._tcp"         = { port = 110 }
    "_pop3s._tcp"        = { port = 995 }
    "_sieve._tcp"        = { port = 4190 }
    "_smtps._tcp"        = { port = 465 }
    "_submission._tcp"   = { port = 587 }
    "_submissions._tcp"  = { port = 465 }
  }

  # SPF authorises the sending host by literal address rather than by the
  # documented "v=spf1 mx a -all". The `a` mechanism resolves the apex,
  # which is Cloudflare-proxied, and would therefore authorise every
  # Cloudflare edge address to send as this domain. Recorded as deviation
  # SPF-1 in the role's decision log.
  # The IPv6 term covers the whole /64 rather than the host's single address.
  # OVH routes the entire /64 to this one machine, so this authorises nothing
  # else, while a bare /128 would fail the moment Docker's NAT66 picked any
  # other source address out of the prefix — kernel source selection is not
  # pinned to the statically configured address.
  mail_spf = "v=spf1 ip4:${var.mail_server_ipv4} ip6:${var.mail_server_ipv6_prefix} -all"

  # A TXT record is a sequence of character-strings, each at most 255 bytes,
  # and Cloudflare stores a long value already split that way. A 2048-bit DKIM
  # key is about 420 bytes, so sending it as one string means the API returns
  # something different from what was sent and every subsequent plan shows an
  # in-place update that never converges. mailcow's dkim_txt is sometimes
  # pre-split and sometimes not, depending on key length, so the quoting is
  # stripped first and reapplied here — one place, one rule.
  mail_dkim_raw    = replace(replace(var.mail_dkim_txt, "\" \"", ""), "\"", "")
  mail_dkim_chunks = [for c in chunklist(split("", local.mail_dkim_raw), 255) : join("", c)]
  mail_dkim_txt    = join(" ", [for c in local.mail_dkim_chunks : "\"${c}\""])

  mail_records = merge(
    {
      # A/AAAA for the mail host. MAILCOW_HOSTNAME, the PTR, the SMTP HELO
      # name and the certificate served on 25/465/587 are all this one name.
      "host/a" = {
        name    = var.mail_hostname
        type    = "A"
        content = var.mail_server_ipv4
        proxied = false
      }
      "host/aaaa" = {
        name    = var.mail_hostname
        type    = "AAAA"
        content = var.mail_server_ipv6
        proxied = false
      }

      "domain/mx" = {
        name     = var.mail_domain
        type     = "MX"
        content  = var.mail_hostname
        priority = 10
      }
      "domain/spf" = {
        name    = var.mail_domain
        type    = "TXT"
        content = "\"${local.mail_spf}\""
      }
      "domain/dmarc" = {
        name    = "_dmarc.${var.mail_domain}"
        type    = "TXT"
        content = "\"v=DMARC1; p=${var.mail_dmarc_policy}; rua=mailto:${var.mail_dmarc_rua}\""
      }

      # mailcow sends watchdog notifications and composes bounces as
      # MAILCOW_HOSTNAME, so the hostname carries its own SPF and DMARC.
      # docs.mailcow.email/post_installation/firststeps-authorize_watchdog_and_bounces/
      "host/spf" = {
        name    = var.mail_hostname
        type    = "TXT"
        content = "\"${local.mail_spf}\""
      }
      "host/dmarc" = {
        name    = "_dmarc.${var.mail_hostname}"
        type    = "TXT"
        content = "\"v=DMARC1; p=${var.mail_dmarc_policy}; rua=mailto:${var.mail_dmarc_rua}\""
      }

      "domain/tls-rpt" = {
        name    = "_smtp._tls.${var.mail_domain}"
        type    = "TXT"
        content = "\"v=TLSRPTv1; rua=mailto:${var.mail_tlsrpt_rua}\""
      }
    },

    # MTA-STS. mailcow serves the policy dynamically from PHP under
    # /.well-known/mta-sts.txt, so the CNAME has to reach mailcow through
    # Traefik. Announcing the policy before anything serves it makes every
    # sender fetch a 404 and emit a TLS-RPT failure, so the announcement is
    # gated and Ansible only flips it once the policy answers 200.
    var.mail_mta_sts_enabled ? {
      "domain/mta-sts" = {
        name    = "_mta-sts.${var.mail_domain}"
        type    = "TXT"
        content = "\"v=STSv1; id=${var.mail_mta_sts_id}\""
      }
    } : {},

    { for a in local.mail_aliases : "alias/${a}" => {
      name    = "${a}.${var.mail_domain}"
      type    = "CNAME"
      content = var.mail_hostname
      proxied = false
    } },

    # Cloudflare mirrors an SRV's priority to the top-level field as well as
    # keeping it inside data. Setting only the nested one leaves the outer
    # attribute null in config against 0 in state, so every subsequent plan
    # reports a spurious in-place update. Both are set, to the same value.
    { for k, v in local.mail_srv : "srv/${k}" => {
      name     = "${k}.${var.mail_domain}"
      type     = "SRV"
      priority = 0
      data = {
        priority = 0
        weight   = 1
        port     = v.port
        target   = var.mail_hostname
      }
    } },

    # SOGo advertises its DAV path through a TXT sibling of the SRV record.
    {
      "srvtxt/caldavs" = {
        name    = "_caldavs._tcp.${var.mail_domain}"
        type    = "TXT"
        content = "\"path=/SOGo/dav/\""
      }
      "srvtxt/carddavs" = {
        name    = "_carddavs._tcp.${var.mail_domain}"
        type    = "TXT"
        content = "\"path=/SOGo/dav/\""
      }
    },

    # DKIM does not exist until mailcow has generated the key for the
    # domain, which cannot happen before the stack is running. Ansible reads
    # the key back out of the mailcow API and passes it in on a later apply;
    # until then the record is simply absent from the plan.
    var.mail_dkim_txt == "" ? {} : {
      "domain/dkim" = {
        name    = "${var.mail_dkim_selector}._domainkey.${var.mail_domain}"
        type    = "TXT"
        content = local.mail_dkim_txt
      }
    },

    # DANE. Accepted and rendered, but nothing populates var.mail_tlsa yet —
    # the role does not compute a digest. Publishing a 3 1 1 record means
    # pinning the certificate's public key, and the current certificate comes
    # from Traefik, whose ACME client generates a fresh key on every renewal.
    # A TLSA published against it would hard-fail delivery from DANE-checking
    # senders at the first renewal. Wiring this up therefore waits on moving
    # the SMTP certificate to a client that reuses its key.
    # Keyed by digest rather than by index, so reordering never churns a plan.
    { for t in var.mail_tlsa : "tlsa/${t.port}/${substr(t.certificate, 0, 16)}" => {
      name = "_${t.port}._tcp.${var.mail_hostname}"
      type = "TLSA"
      data = {
        usage         = t.usage
        selector      = t.selector
        matching_type = t.matching_type
        certificate   = t.certificate
      }
    } },
  )
}

# internet.nl scores DNSSEC as one of five equally weighted categories and
# ignores any TLSA RRset that is not DNSSEC-secure, so DANE is unreachable
# without this. Turning on signing at Cloudflare is safe on its own: the zone
# stays unvalidated, and therefore behaves exactly as today, until a DS record
# is published at the registrar. That last step is the one thing here no
# credential in this repo can reach — joachimjasmin.com is registered at
# Squarespace, not Cloudflare — so the DS is surfaced as an output instead.
resource "cloudflare_zone_dnssec" "mail" {
  count = var.mail_dnssec_enabled ? 1 : 0

  zone_id = local.mail_zone_id
  status  = "active"

  lifecycle {
    # Cloudflare reports "pending" from the moment signing is switched on
    # until it detects the DS at the registrar, and there is no API call that
    # moves it on — only the registrar can. Without this, every plan for as
    # long as the DS is missing carries one in-place update that can never
    # succeed, which would make an empty plan impossible to reach. The real
    # signal lives in the role's verify step, which reads the DS out of DNS
    # and says plainly that the zone is unsigned.
    ignore_changes = [status]
  }
}

resource "cloudflare_dns_record" "mail" {
  for_each = local.mail_records

  zone_id  = local.mail_zone_id
  name     = each.value.name
  type     = each.value.type
  ttl      = var.mail_ttl
  content  = try(each.value.content, null)
  data     = try(each.value.data, null)
  priority = try(each.value.priority, null)
  proxied  = try(each.value.proxied, null)
  comment  = "mailcow — terraform, driven by the ansible mailcow role"
}
