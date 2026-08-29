terraform {
  # variables.tf marks the Cloudflare token `ephemeral`, which is 1.10 and
  # later. Without this pin an older control node fails inside the role with
  # an unhelpful parse error rather than a version message.
  required_version = ">= 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.22.0"
    }
  }

  backend "s3" {
    bucket = "tfstate"
    key    = "cloudflare/dns.tfstate"
    region = "auto"

    endpoints                   = { s3 = "https://84f68fd6001a83cc4b721288f66135fe.r2.cloudflarestorage.com" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_lockfile                = true
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
