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

# ------------------------------------------------------------------ #
#                          Mail DNS (mailcow)                        #
# ------------------------------------------------------------------ #

variable "mail_domain" {
  type        = string
  description = "Zone the mailboxes live in. Must be a key of zone_ids."
}

variable "mail_hostname" {
  type        = string
  description = "MAILCOW_HOSTNAME. Also the PTR, the SMTP HELO name and the CN of the certificate served on 25/465/587 — the three have to agree."
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
  description = "Sign the mail zone at Cloudflare. Harmless on its own — the zone stays unvalidated, and so behaves exactly as before, until the DS is published at the registrar."
  default     = true
}

variable "mail_mta_sts_enabled" {
  type        = bool
  description = "Announce the MTA-STS policy. Stays false until mailcow actually serves /.well-known/mta-sts.txt — announcing a policy nobody serves makes senders fetch a 404 and file TLS-RPT failures."
  default     = false
}

variable "mail_ttl" {
  type        = number
  description = "TTL for every mail record. Low on purpose — DKIM and TLSA change during a rebuild."
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
  description = "Mailbox receiving DMARC aggregate reports."
}

variable "mail_tlsrpt_rua" {
  type        = string
  description = "Mailbox receiving SMTP TLS reports."
}

variable "mail_mta_sts_id" {
  type        = string
  description = "MTA-STS policy id. Must change whenever the policy body changes."
}

variable "mail_dkim_selector" {
  type        = string
  description = "DKIM selector mailcow signs with."
  default     = "dkim"
}

variable "mail_dkim_txt" {
  type        = string
  description = <<-EOT
    Full DKIM record value, taken verbatim from the mailcow API's dkim_txt
    field. Deliberately not the bare public key: a 2048-bit key overruns the
    255-byte limit on a single TXT character-string, and mailcow already
    emits the correctly split "chunk" "chunk" form. Rebuilding it here would
    reimplement that splitting, badly. Empty until mailcow has generated the
    key, which keeps the record out of the plan entirely.
  EOT
  default     = ""
}

variable "mail_tlsa" {
  type = list(object({
    port          = number
    usage         = number
    selector      = number
    matching_type = number
    certificate   = string
  }))
  description = "DANE records. Empty until the zone is signed — internet.nl ignores a TLSA RRset that is not DNSSEC-secure, and mail delivery breaks if one is published against an unsigned zone."
  default     = []

  validation {
    condition     = alltrue([for t in var.mail_tlsa : contains([2, 3], t.usage)])
    error_message = "internet.nl ignores TLSA usage 0 and 1 on port 25; use DANE-TA(2) or DANE-EE(3)."
  }
}
