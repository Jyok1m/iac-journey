# Mail DNS, kept out of cloudflare_dns_record.this so a change here cannot put
# ten unrelated apex/wildcard records in its blast radius.
#
# Every record here is unproxied: the apex and wildcard are proxied, so an
# exact-name record is what keeps these off the Cloudflare edge — an MX
# pointing at the HTTP proxy accepts no SMTP.
#
# One host, several domains: mail_hostname is shared, so there is one A/AAAA,
# one PTR, one HELO name and one certificate. Per-domain is only what a
# receiver checks against the envelope sender.

locals {
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

  # Served over HTTPS by Traefik, so they must reach the host directly for
  # ACME — CNAMEs onto the unproxied hostname, not proxied records.
  mail_client_aliases = ["autodiscover", "autoconfig"]

  # docs.mailcow.email/getstarted/prerequisite-dns/
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

  # Literal addresses, not the documented "v=spf1 mx a -all": `a` resolves the
  # proxied apex and would authorise every Cloudflare edge address to send as
  # this domain. Deviation SPF-1 in the role's decision log.
  # The /64 rather than a /128: OVH routes the whole prefix here, and kernel
  # source selection is not pinned to the configured address.
  mail_spf = "v=spf1 ip4:${var.mail_server_ipv4} ip6:${var.mail_server_ipv6_prefix} -all"

  # TXT strings cap at 255 bytes and Cloudflare stores a long value already
  # split; sending a ~420-byte DKIM key as one string makes every plan show an
  # update that never converges. mailcow's dkim_txt is sometimes pre-split, so
  # the quoting is stripped and reapplied here — one place, one rule.
  mail_dkim_raw = {
    for d, txt in var.mail_dkim : d => replace(replace(txt, "\" \"", ""), "\"", "")
    if txt != "" && contains(keys(var.mail_domains), d)
  }
  mail_dkim_txt = {
    for d, raw in local.mail_dkim_raw :
    d => join(" ", [for c in chunklist(split("", raw), 255) : "\"${join("", c)}\""])
  }

  # Once, on the mail host itself. mailcow sends watchdog notifications and
  # composes bounces as this name, so it carries its own SPF and DMARC.
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

  # Once per domain.
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

      # The TXT is gated on Ansible having seen the policy answer 200:
      # announcing it early makes every sender fetch a 404 and report it.
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

      # Cloudflare mirrors priority to the top-level field as well as into
      # data; setting only the nested one makes every plan show an update.
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

  # Absent from the plan until mailcow has generated the key and Ansible has
  # read it back out of the API on a later apply.
  mail_dkim_records = {
    for d, txt in local.mail_dkim_txt : "${d}/dkim" => {
      zone_id = local.mail_domains[d].zone_id
      name    = "${var.mail_dkim_selector}._domainkey.${d}"
      type    = "TXT"
      content = txt
    }
  }

  # RFC 7489 §7.1 — external destination authorisation. Reports for every
  # domain land in one mailbox, and without these records a receiver silently
  # sends nothing. The check is on the literal domain, so mail.<domain> needs
  # one too. zone_ids is indexed directly: an unmanaged report zone is a
  # configuration error and should fail at plan time.
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

  # DANE, rendered but unpopulated: Traefik's ACME client generates a fresh
  # key on every renewal, and a TLSA pinned to it would hard-fail delivery at
  # the first one. Waits on an SMTP certificate from a client that reuses its
  # key. Keyed by digest so reordering never churns a plan.
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

# DANE is unreachable without this: a TLSA RRset that is not DNSSEC-secure is
# ignored. Signing alone is safe — the zone stays unvalidated until a DS is
# published at the registrar, which nothing here can reach, so the DS values
# are surfaced as an output instead.
resource "cloudflare_zone_dnssec" "mail" {
  for_each = local.mail_dnssec_domains

  zone_id = var.zone_ids[each.key]
  status  = "active"

  lifecycle {
    # Stays "pending" until Cloudflare detects the DS at the registrar, and no
    # API call moves it on — without this an empty plan is unreachable. The
    # role's verify step reports which zones are actually unsigned.
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
