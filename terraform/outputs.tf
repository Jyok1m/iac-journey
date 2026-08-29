# The DS record the registrar needs. Cloudflare signs the zone as soon as
# cloudflare_zone_dnssec is active, but the chain of trust only closes once
# this value is published at the registrar, which no credential in this repo
# can reach. The role's verify step reads the DS out of live DNS and, if it is
# missing, prints the command below rather than letting the DNSSEC-dependent
# checks quietly score zero.
output "mail_dnssec_ds" {
  description = "DS record to publish at the registrar for the mail domain."
  value       = var.mail_dnssec_enabled ? one(cloudflare_zone_dnssec.mail[*].ds) : null
}

output "mail_dnssec_status" {
  description = "Cloudflare-side DNSSEC status for the mail zone."
  value       = var.mail_dnssec_enabled ? one(cloudflare_zone_dnssec.mail[*].status) : "disabled"
}

output "mail_dnssec_digest" {
  description = "Digest, key tag, algorithm and digest type, for registrars that ask for the DS in parts rather than as one string."
  value = var.mail_dnssec_enabled ? {
    key_tag          = one(cloudflare_zone_dnssec.mail[*].key_tag)
    algorithm        = one(cloudflare_zone_dnssec.mail[*].algorithm)
    digest_type      = one(cloudflare_zone_dnssec.mail[*].digest_type)
    digest           = one(cloudflare_zone_dnssec.mail[*].digest)
    digest_algorithm = one(cloudflare_zone_dnssec.mail[*].digest_algorithm)
  } : null
}

# Everything the mail setup published, so a run can diff what it believes it
# created against what dig actually returns.
output "mail_records" {
  description = "Name and type of every mail DNS record under management."
  value       = { for k, r in cloudflare_dns_record.mail : k => "${r.type} ${r.name}" }
}
