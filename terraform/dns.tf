locals {
  records = merge([
    for domain, zone_id in var.zone_ids : {
      "${domain}/apex" = {
        zone_id = zone_id
        name    = domain
        type    = "A"
        content = var.portfolio_server_ip
      }
      "${domain}/wildcard" = {
        zone_id = zone_id
        name    = "*.${domain}"
        type    = "A"
        content = var.portfolio_server_ip
      }
    }
  ]...)
}

resource "cloudflare_dns_record" "this" {
  for_each = local.records

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content
  proxied = true
  ttl     = 1
}
