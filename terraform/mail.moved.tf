# One-off key migration, kept forever. Going multi-domain moved the domain into
# the resource key, which Terraform reads as delete-then-create, and
# terraform_apply.yml refuses any plan containing a delete.
#
# No-ops once the state has moved, but kept: removing them would strand anyone
# restoring an older state. The literal domain is history, not configuration,
# and must not follow var.mail_domain.

moved {
  from = cloudflare_zone_dnssec.mail[0]
  to   = cloudflare_zone_dnssec.mail["joachimjasmin.com"]
}

moved {
  from = cloudflare_dns_record.mail["alias/autoconfig"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/alias/autoconfig"]
}

moved {
  from = cloudflare_dns_record.mail["alias/autodiscover"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/alias/autodiscover"]
}

moved {
  from = cloudflare_dns_record.mail["alias/mta-sts"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/alias/mta-sts"]
}

moved {
  from = cloudflare_dns_record.mail["domain/dkim"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/dkim"]
}

moved {
  from = cloudflare_dns_record.mail["domain/dmarc"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/dmarc"]
}

moved {
  from = cloudflare_dns_record.mail["domain/mx"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/mx"]
}

moved {
  from = cloudflare_dns_record.mail["domain/spf"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/spf"]
}

moved {
  from = cloudflare_dns_record.mail["domain/tls-rpt"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/tls-rpt"]
}

moved {
  from = cloudflare_dns_record.mail["srv/_autodiscover._tcp"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srv/_autodiscover._tcp"]
}

moved {
  from = cloudflare_dns_record.mail["srv/_caldavs._tcp"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srv/_caldavs._tcp"]
}

moved {
  from = cloudflare_dns_record.mail["srv/_carddavs._tcp"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srv/_carddavs._tcp"]
}

moved {
  from = cloudflare_dns_record.mail["srv/_imap._tcp"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srv/_imap._tcp"]
}

moved {
  from = cloudflare_dns_record.mail["srv/_imaps._tcp"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srv/_imaps._tcp"]
}

moved {
  from = cloudflare_dns_record.mail["srv/_pop3._tcp"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srv/_pop3._tcp"]
}

moved {
  from = cloudflare_dns_record.mail["srv/_pop3s._tcp"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srv/_pop3s._tcp"]
}

moved {
  from = cloudflare_dns_record.mail["srv/_sieve._tcp"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srv/_sieve._tcp"]
}

moved {
  from = cloudflare_dns_record.mail["srv/_smtps._tcp"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srv/_smtps._tcp"]
}

moved {
  from = cloudflare_dns_record.mail["srv/_submission._tcp"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srv/_submission._tcp"]
}

moved {
  from = cloudflare_dns_record.mail["srv/_submissions._tcp"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srv/_submissions._tcp"]
}

moved {
  from = cloudflare_dns_record.mail["srvtxt/caldavs"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srvtxt/caldavs"]
}

moved {
  from = cloudflare_dns_record.mail["srvtxt/carddavs"]
  to   = cloudflare_dns_record.mail["joachimjasmin.com/srvtxt/carddavs"]
}
