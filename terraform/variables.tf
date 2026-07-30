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
