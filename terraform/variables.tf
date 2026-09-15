variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "zone_ids" {
  type        = map(string)
  description = "Zone IDs Cloudflare, clé = slug de la zone"
}

variable "portfolio_server_ip" {
  type = string
}

# Mail DNS (mailcow)

variable "mail_hostname" {
  type        = string
  description = "MAILCOW_HOSTNAME. Also the PTR, the SMTP HELO name and the CN of the certificate served on 25/465/587: the three have to agree. One host serves every domain below, so this name is deliberately NOT per-domain."
}

variable "mail_domain" {
  type        = string
  description = "The zone mail_hostname itself lives in. Its A/AAAA and the host's own SPF and DMARC land here. Must be a key of mail_domains."

  validation {
    condition     = contains(keys(var.mail_domains), var.mail_domain)
    error_message = "mail_domain must also appear as a key of mail_domains."
  }
}

variable "mail_domains" {
  type = map(object({
    # MTA-STS policy id. Must change whenever the policy body changes.
    mta_sts_id = string

    # autodiscover/autoconfig CNAMEs, SRV set and DAV path hints. Pure noise
    # for a domain that only ever sends from a no-reply address.
    client_autoconfig = optional(bool, true)

    # The mta-sts CNAME, and the TXT once mailcow serves the policy. About how
    # other MTAs deliver to us, not how our own clients connect.
    mta_sts = optional(bool, true)

    # Both fall back to the repo-wide mailbox.
    dmarc_rua  = optional(string)
    tlsrpt_rua = optional(string)
  }))
  description = "Every domain mailcow sends and receives for, keyed by zone name."

  validation {
    condition     = alltrue([for d in keys(var.mail_domains) : contains(keys(var.zone_ids), d)])
    error_message = "Every key of mail_domains must also be a key of zone_ids: the records are written into that zone."
  }
}

variable "mail_server_ipv4" {
  type        = string
  description = "Address the MX resolves to. Kept separate from portfolio_server_ip: that one is proxied, this one must not be."
}

variable "mail_server_ipv6" {
  type        = string
  description = "AAAA for the MX. internet.nl caps the score at 90% without it."
}

variable "mail_server_ipv6_prefix" {
  type        = string
  description = "IPv6 range authorised to send, as an SPF ip6: term. The whole /64 is routed to this one host, so covering the prefix rather than the single address costs nothing and survives Docker picking another source address out of it."
}

variable "mail_dnssec_enabled" {
  type        = bool
  description = "Sign the mail zones at Cloudflare. Harmless on its own: a zone stays unvalidated, and so behaves exactly as before, until its DS is published at the registrar."
  default     = true
}

variable "mail_dnssec_domains" {
  type        = set(string)
  description = "Which mail zones to sign. null means every key of mail_domains. Signing costs nothing until the DS is published, but each zone's DS has to be pasted at its own registrar, so this exists to sign a subset."
  default     = null

  validation {
    condition = var.mail_dnssec_domains == null || alltrue([
      for d in coalesce(var.mail_dnssec_domains, []) : contains(keys(var.mail_domains), d)
    ])
    error_message = "mail_dnssec_domains may only name domains that are keys of mail_domains."
  }
}

variable "mail_ttl" {
  type        = number
  description = "TTL for every mail record. Low on purpose: DKIM and TLSA change during a rebuild."
  default     = 300
}

variable "mail_dmarc_policy" {
  type        = string
  description = "DMARC p=. internet.nl awards full marks from quarantine upwards."
  default     = "reject"

  validation {
    condition     = contains(["none", "quarantine", "reject"], var.mail_dmarc_policy)
    error_message = "mail_dmarc_policy must be none, quarantine or reject."
  }
}

variable "mail_dmarc_rua" {
  type        = string
  description = "Default mailbox receiving DMARC aggregate reports. A domain whose reports land outside itself also needs an RFC 7489 authorisation record, which this configuration derives and publishes."
}

variable "mail_tlsrpt_rua" {
  type        = string
  description = "Default mailbox receiving SMTP TLS reports. Unlike DMARC, RFC 8460 requires no authorisation record for an external destination."
}

variable "mail_dkim_selector" {
  type        = string
  description = "DKIM selector mailcow signs with. One selector for every domain: mailcow keys are per-domain, the selector name is not."
  default     = "dkim"
}

variable "mail_dkim" {
  type        = map(string)
  description = <<-EOT
    Full DKIM record value per domain, taken verbatim from the mailcow API's
    dkim_txt field. Deliberately not the bare public key: a 2048-bit key
    overruns the 255-byte limit on a single TXT character-string, and mailcow
    already emits the correctly split "chunk" "chunk" form. Rebuilding it here
    would reimplement that splitting, badly. A domain missing from this map, or
    mapped to "", keeps its DKIM record out of the plan entirely, which is the
    state on the pass that runs before mailcow exists.
  EOT
  default     = {}
}

variable "mail_mta_sts_serving" {
  type        = map(bool)
  description = "Per domain: is mailcow actually answering /.well-known/mta-sts.txt for it yet. Announcing a policy nobody serves makes senders fetch a 404 and file TLS-RPT failures, so the TXT is gated on this and Ansible flips it once the policy answers 200."
  default     = {}
}

variable "mail_tlsa" {
  type = list(object({
    port          = number
    usage         = number
    selector      = number
    matching_type = number
    certificate   = string
  }))
  description = "DANE records. Empty until the zone is signed: internet.nl ignores a TLSA RRset that is not DNSSEC-secure, and mail delivery breaks if one is published against an unsigned zone."
  default     = []

  validation {
    condition     = alltrue([for t in var.mail_tlsa : contains([2, 3], t.usage)])
    error_message = "internet.nl ignores TLSA usage 0 and 1 on port 25; use DANE-TA(2) or DANE-EE(3)."
  }
}
