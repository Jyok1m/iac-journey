# ------------------------------------------------------------------ #
#                          Mail DNS (mailcow)                        #
# ------------------------------------------------------------------ #
# Deliberately a separate resource from cloudflare_dns_record.this.
# That one owns the apex and the wildcard for all five zones behind a
# for_each keyed on "<zone>/<slot>"; folding mail records into its map
# would put ten live, unrelated records inside the blast radius of every
# change made here. A second resource shares nothing but the provider.
#
# Every record below is unproxied. Each zone's apex and wildcard are
# proxied, so autoconfig.<domain> and mta-sts.<domain> resolve to a
# Cloudflare edge address until an explicit record exists for that name —
# and an MX pointing at the HTTP proxy accepts no SMTP. An exact-name
# record wins over the wildcard without modifying it.
#
# ONE HOST, SEVERAL DOMAINS. mail_hostname is not per-domain: every domain's
# MX points at the same name, so there is one A/AAAA, one PTR, one HELO name
# and one certificate. What is per-domain is everything a receiver checks
# against the envelope sender: MX, SPF, DKIM, DMARC, TLS-RPT, MTA-STS.

locals {
  # Per-domain settings with the repo-wide report destinations filled in.
  mail_domains = {
    for d, cfg in var.mail_domains : d => {
      zone_id           = var.zone_ids[d]
      mta_sts_id        = cfg.mta_sts_id
      client_autoconfig = cfg.client_autoconfig
      mta_sts           = cfg.mta_sts
      dmarc_rua         = coalesce(cfg.dmarc_rua, var.mail_dmarc_rua)
      tlsrpt_rua        = coalesce(cfg.tlsrpt_rua, var.mail_tlsrpt_rua)
    }
  }

  mail_zone_id = var.zone_ids[var.mail_domain]

  mail_dnssec_domains = (
    var.mail_dnssec_enabled
    ? (var.mail_dnssec_domains == null ? toset(keys(var.mail_domains)) : var.mail_dnssec_domains)
    : toset([])
  )

  # Client autoconfiguration endpoints. Both are served over HTTPS by Traefik
  # and so must reach the host directly for ACME — hence CNAMEs onto the
  # unproxied hostname rather than proxied records of their own.
  mail_client_aliases = ["autodiscover", "autoconfig"]

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
  # Identical for every domain: one host sends for all of them.
  mail_spf = "v=spf1 ip4:${var.mail_server_ipv4} ip6:${var.mail_server_ipv6_prefix} -all"

  # A TXT record is a sequence of character-strings, each at most 255 bytes,
  # and Cloudflare stores a long value already split that way. A 2048-bit DKIM
  # key is about 420 bytes, so sending it as one string means the API returns
  # something different from what was sent and every subsequent plan shows an
  # in-place update that never converges. mailcow's dkim_txt is sometimes
  # pre-split and sometimes not, depending on key length, so the quoting is
  # stripped first and reapplied here — one place, one rule.
  mail_dkim_raw = {
    for d, txt in var.mail_dkim : d => replace(replace(txt, "\" \"", ""), "\"", "")
    if txt != "" && contains(keys(var.mail_domains), d)
  }
  mail_dkim_txt = {
    for d, raw in local.mail_dkim_raw :
    d => join(" ", [for c in chunklist(split("", raw), 255) : "\"${join("", c)}\""])
  }

  # ---------------------------------------------------------------- #
  # Records that exist exactly once, on the mail host itself.
  # ---------------------------------------------------------------- #
  # MAILCOW_HOSTNAME, the PTR, the SMTP HELO name and the certificate served
  # on 25/465/587 are all this one name. mailcow also sends watchdog
  # notifications and composes bounces as it, so the hostname carries its own
  # SPF and DMARC on top of the A/AAAA.
  # docs.mailcow.email/post_installation/firststeps-authorize_watchdog_and_bounces/
  mail_host_records = {
    "host/a" = {
      zone_id = local.mail_zone_id
      name    = var.mail_hostname
      type    = "A"
      content = var.mail_server_ipv4
      proxied = false
    }
    "host/aaaa" = {
      zone_id = local.mail_zone_id
      name    = var.mail_hostname
      type    = "AAAA"
      content = var.mail_server_ipv6
      proxied = false
    }
    "host/spf" = {
      zone_id = local.mail_zone_id
      name    = var.mail_hostname
      type    = "TXT"
      content = "\"${local.mail_spf}\""
    }
    "host/dmarc" = {
      zone_id = local.mail_zone_id
      name    = "_dmarc.${var.mail_hostname}"
      type    = "TXT"
      content = "\"v=DMARC1; p=${var.mail_dmarc_policy}; rua=mailto:${var.mail_dmarc_rua}\""
    }
  }

  # ---------------------------------------------------------------- #
  # Records that exist once per domain.
  # ---------------------------------------------------------------- #
  mail_domain_records = merge([
    for d, cfg in local.mail_domains : merge(
      {
        "${d}/mx" = {
          zone_id  = cfg.zone_id
          name     = d
          type     = "MX"
          content  = var.mail_hostname
          priority = 10
        }
        "${d}/spf" = {
          zone_id = cfg.zone_id
          name    = d
          type    = "TXT"
          content = "\"${local.mail_spf}\""
        }
        "${d}/dmarc" = {
          zone_id = cfg.zone_id
          name    = "_dmarc.${d}"
          type    = "TXT"
          content = "\"v=DMARC1; p=${var.mail_dmarc_policy}; rua=mailto:${cfg.dmarc_rua}\""
        }
        "${d}/tls-rpt" = {
          zone_id = cfg.zone_id
          name    = "_smtp._tls.${d}"
          type    = "TXT"
          content = "\"v=TLSRPTv1; rua=mailto:${cfg.tlsrpt_rua}\""
        }
      },

      # MTA-STS. mailcow serves the policy dynamically from PHP under
      # /.well-known/mta-sts.txt, so the CNAME has to reach mailcow through
      # Traefik. Announcing the policy before anything serves it makes every
      # sender fetch a 404 and emit a TLS-RPT failure, so the TXT is gated on
      # Ansible having seen the policy answer 200 for this exact domain.
      cfg.mta_sts ? {
        "${d}/alias/mta-sts" = {
          zone_id = cfg.zone_id
          name    = "mta-sts.${d}"
          type    = "CNAME"
          content = var.mail_hostname
          proxied = false
        }
      } : {},
      cfg.mta_sts && try(var.mail_mta_sts_serving[d], false) ? {
        "${d}/mta-sts" = {
          zone_id = cfg.zone_id
          name    = "_mta-sts.${d}"
          type    = "TXT"
          content = "\"v=STSv1; id=${cfg.mta_sts_id}\""
        }
      } : {},

      cfg.client_autoconfig ? { for a in local.mail_client_aliases : "${d}/alias/${a}" => {
        zone_id = cfg.zone_id
        name    = "${a}.${d}"
        type    = "CNAME"
        content = var.mail_hostname
        proxied = false
      } } : {},

      # Cloudflare mirrors an SRV's priority to the top-level field as well as
      # keeping it inside data. Setting only the nested one leaves the outer
      # attribute null in config against 0 in state, so every subsequent plan
      # reports a spurious in-place update. Both are set, to the same value.
      cfg.client_autoconfig ? { for k, v in local.mail_srv : "${d}/srv/${k}" => {
        zone_id  = cfg.zone_id
        name     = "${k}.${d}"
        type     = "SRV"
        priority = 0
        data = {
          priority = 0
          weight   = 1
          port     = v.port
          target   = var.mail_hostname
        }
      } } : {},

      # SOGo advertises its DAV path through a TXT sibling of the SRV record.
      cfg.client_autoconfig ? {
        "${d}/srvtxt/caldavs" = {
          zone_id = cfg.zone_id
          name    = "_caldavs._tcp.${d}"
          type    = "TXT"
          content = "\"path=/SOGo/dav/\""
        }
        "${d}/srvtxt/carddavs" = {
          zone_id = cfg.zone_id
          name    = "_carddavs._tcp.${d}"
          type    = "TXT"
          content = "\"path=/SOGo/dav/\""
        }
      } : {},
    )
  ]...)

  # DKIM does not exist until mailcow has generated the key for the domain,
  # which cannot happen before the stack is running. Ansible reads each key
  # back out of the mailcow API and passes it in on a later apply; until then
  # the record is simply absent from the plan.
  mail_dkim_records = {
    for d, txt in local.mail_dkim_txt : "${d}/dkim" => {
      zone_id = local.mail_domains[d].zone_id
      name    = "${var.mail_dkim_selector}._domainkey.${d}"
      type    = "TXT"
      content = txt
    }
  }

  # ---------------------------------------------------------------- #
  # RFC 7489 §7.1 — external destination authorisation.
  # ---------------------------------------------------------------- #
  # A receiver MUST NOT send aggregate reports to a mailbox outside the domain
  # the DMARC record belongs to unless that other domain says so, by publishing
  # "v=DMARC1" at <policy-domain>._report._dmarc.<report-domain>. Reports for
  # every domain here land in one mailbox on {var.mail_domain}, so without
  # these records the whole point of p=reject — seeing who is forging the
  # domain — silently produces nothing. The check is on the literal domain, not
  # the organisational one, so mail.<domain> needs one too.
  #
  # var.zone_ids is indexed directly rather than looked up with a fallback: a
  # report mailbox in a zone this repo does not manage is a configuration
  # error, and failing at plan time is the right outcome.
  mail_report_auth = merge([
    for d, target in merge(
      { for d, cfg in local.mail_domains : d => element(split("@", cfg.dmarc_rua), 1) },
      { (var.mail_hostname) = element(split("@", var.mail_dmarc_rua), 1) },
      ) : target == d ? {} : {
      "${d}/report-auth" = {
        zone_id = var.zone_ids[target]
        name    = "${d}._report._dmarc.${target}"
        type    = "TXT"
        content = "\"v=DMARC1\""
      }
    }
  ]...)

  # DANE. Accepted and rendered, but nothing populates var.mail_tlsa yet —
  # the role does not compute a digest. Publishing a 3 1 1 record means
  # pinning the certificate's public key, and the current certificate comes
  # from Traefik, whose ACME client generates a fresh key on every renewal.
  # A TLSA published against it would hard-fail delivery from DANE-checking
  # senders at the first renewal. Wiring this up therefore waits on moving
  # the SMTP certificate to a client that reuses its key.
  # Keyed by digest rather than by index, so reordering never churns a plan.
  # The host is shared, so these live in the hostname's zone only.
  mail_tlsa_records = { for t in var.mail_tlsa : "tlsa/${t.port}/${substr(t.certificate, 0, 16)}" => {
    zone_id = local.mail_zone_id
    name    = "_${t.port}._tcp.${var.mail_hostname}"
    type    = "TLSA"
    data = {
      usage         = t.usage
      selector      = t.selector
      matching_type = t.matching_type
      certificate   = t.certificate
    }
  } }

  mail_records = merge(
    local.mail_host_records,
    local.mail_domain_records,
    local.mail_dkim_records,
    local.mail_report_auth,
    local.mail_tlsa_records,
  )
}

# internet.nl scores DNSSEC as one of five equally weighted categories and
# ignores any TLSA RRset that is not DNSSEC-secure, so DANE is unreachable
# without this. Turning on signing at Cloudflare is safe on its own: the zone
# stays unvalidated, and therefore behaves exactly as today, until a DS record
# is published at the registrar. That last step is the one thing here no
# credential in this repo can reach — the zones are hosted at Cloudflare but
# registered elsewhere — so the DS values are surfaced as an output instead.
resource "cloudflare_zone_dnssec" "mail" {
  for_each = local.mail_dnssec_domains

  zone_id = var.zone_ids[each.key]
  status  = "active"

  lifecycle {
    # Cloudflare reports "pending" from the moment signing is switched on
    # until it detects the DS at the registrar, and there is no API call that
    # moves it on — only the registrar can. Without this, every plan for as
    # long as the DS is missing carries one in-place update that can never
    # succeed, which would make an empty plan impossible to reach. The real
    # signal lives in the role's verify step, which reads the DS out of DNS
    # and says plainly which zones are unsigned.
    ignore_changes = [status]
  }
}

resource "cloudflare_dns_record" "mail" {
  for_each = local.mail_records

  zone_id  = each.value.zone_id
  name     = each.value.name
  type     = each.value.type
  ttl      = var.mail_ttl
  content  = try(each.value.content, null)
  data     = try(each.value.data, null)
  priority = try(each.value.priority, null)
  proxied  = try(each.value.proxied, null)
  comment  = "mailcow — terraform, driven by the ansible mailcow role"
}
