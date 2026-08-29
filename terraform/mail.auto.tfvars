# Mail DNS inputs that are known ahead of time and edited by hand.
# The values that cannot be — the DKIM record and the MTA-STS switch — are
# written by the ansible mailcow role into mail.generated.auto.tfvars.
# No secret here, and none there either: a DKIM public key is published in
# DNS by definition.

mail_domain   = "joachimjasmin.com"
mail_hostname = "mail.joachimjasmin.com"

# Deliberately not portfolio_server_ip. That variable feeds the proxied apex
# and wildcard; these two records must stay unproxied, and the split keeps a
# future change to one from silently moving the other.
mail_server_ipv4        = "51.255.74.84"
mail_server_ipv6        = "2001:41d0:1004:2654::"
mail_server_ipv6_prefix = "2001:41d0:1004:2654::/64"

mail_dmarc_policy = "reject"
mail_dmarc_rua    = "dmarc@joachimjasmin.com"
mail_tlsrpt_rua   = "tls-reports@joachimjasmin.com"

# Bump whenever the MTA-STS policy body changes.
mail_mta_sts_id = "20260813000001"
