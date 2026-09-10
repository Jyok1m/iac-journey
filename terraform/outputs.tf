# The DS record each registrar needs, keyed by zone. Cloudflare signs a zone as
# soon as its cloudflare_zone_dnssec is active, but the chain of trust only
# closes once this value is published at the registrar, which no credential in
# this repo can reach — the three mail zones are hosted at Cloudflare and
# registered elsewhere. The role's verify step reads each DS out of live DNS
# and, where it is missing, prints the value rather than letting the
# DNSSEC-dependent checks quietly score zero.
output "mail_dnssec_ds" {
  description = "DS record to publish at the registrar, per signed mail zone."
  value       = { for d, z in cloudflare_zone_dnssec.mail : d => z.ds }
}

output "mail_dnssec_status" {
  description = "Cloudflare-side DNSSEC status per mail zone. Zones absent from mail_dnssec_domains are reported as disabled rather than omitted."
  value = merge(
    { for d in keys(var.mail_domains) : d => "disabled" },
    { for d, z in cloudflare_zone_dnssec.mail : d => z.status },
  )
}

output "mail_dnssec_digest" {
  description = "Digest, key tag, algorithm and digest type per signed zone, for registrars that ask for the DS in parts rather than as one string."
  value = { for d, z in cloudflare_zone_dnssec.mail : d => {
    key_tag          = z.key_tag
    algorithm        = z.algorithm
    digest_type      = z.digest_type
    digest           = z.digest
    digest_algorithm = z.digest_algorithm
  } }
}

# Everything the mail setup published, so a run can diff what it believes it
# created against what dig actually returns.
output "mail_records" {
  description = "Name and type of every mail DNS record under management."
  value       = { for k, r in cloudflare_dns_record.mail : k => "${r.type} ${r.name}" }
}
