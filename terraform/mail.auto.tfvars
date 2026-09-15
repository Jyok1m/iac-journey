# Mail DNS inputs that are known ahead of time and edited by hand.
# The values that cannot be (the DKIM keys and the MTA-STS switches) are
# written by the ansible mailcow role into mail.generated.auto.tfvars.
# No secret here, and none there either: a DKIM public key is published in
# DNS by definition.

# ------------------------------------------------------------------ #
#                            The mail host                           #
# ------------------------------------------------------------------ #
# One host serves every domain below. This name is the SMTP HELO name, the
# PTR target and the CN of the certificate on 25/465/587, so it is a property
# of the machine and not of any one domain: adding a domain does not add a
# hostname, an address, a certificate or a reverse record.
mail_hostname = "mail.joachimjasmin.com"

# The zone mail_hostname itself lives in. Its A/AAAA and the host's own SPF
# and DMARC are written here.
mail_domain = "joachimjasmin.com"

# Deliberately not portfolio_server_ip. That variable feeds the proxied apex
# and wildcard; these two records must stay unproxied, and the split keeps a
# future change to one from silently moving the other.
mail_server_ipv4        = "51.255.74.84"
mail_server_ipv6        = "2001:41d0:1004:2654::"
mail_server_ipv6_prefix = "2001:41d0:1004:2654::/64"

# ------------------------------------------------------------------ #
#                              The domains                           #
# ------------------------------------------------------------------ #
# Every key must also be a key of zone_ids: the records go into that zone.
#
# mta_sts_id has to change whenever the policy body changes, and it is
# per-domain because the announcement is per-domain. The convention is the
# date it last changed plus a counter.
#
# client_autoconfig publishes the autodiscover/autoconfig CNAMEs, the eleven
# SRV records and the DAV path hints. Left on for a domain whose mailboxes get
# opened in a mail client; turned off for one that only ever sends from a
# no-reply address, where those records would be fourteen names nobody
# resolves and three more certificates for Traefik to renew.
mail_domains = {
  "joachimjasmin.com" = {
    mta_sts_id = "20260813000001"
  }

  # helenedm@ is a human mailbox, read in a real client.
  "ipseis.eu" = {
    mta_sts_id = "20260910000001"
  }

  # no-reply@ only, sent from the app. Nothing here is ever opened in a mail
  # client, so the client autoconfiguration records are left unpublished.
  "odyssai.app" = {
    mta_sts_id        = "20260910000001"
    client_autoconfig = false
  }
}

# ------------------------------------------------------------------ #
#                              Reporting                             #
# ------------------------------------------------------------------ #
# One destination for all three domains. Because those mailboxes sit outside
# ipseis.eu and odyssai.app, RFC 7489 makes the reports conditional on an
# authorisation record in this zone: mail.tf derives and publishes those.
mail_dmarc_policy = "reject"
mail_dmarc_rua    = "dmarc@joachimjasmin.com"
mail_tlsrpt_rua   = "tls-reports@joachimjasmin.com"

# ------------------------------------------------------------------ #
#                               DNSSEC                               #
# ------------------------------------------------------------------ #
# Signing a zone at Cloudflare is free and reversible, but the chain of trust
# only closes once that zone's DS is pasted at its own registrar, and each of
# these three is registered somewhere different. Only the zone that has been
# through that is listed; add the others here once you are ready to publish
# their DS, and read the values out with
#   terraform output mail_dnssec_ds
mail_dnssec_domains = ["joachimjasmin.com"]
