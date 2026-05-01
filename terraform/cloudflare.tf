# Generate a 35-character secret for the tunnel
resource "random_password" "tunnel_secret" {
  length  = 35
  special = false
}

# Traefik DNS-01 API Token
data "cloudflare_api_token_permission_groups" "all" {}

resource "cloudflare_api_token" "traefik_dns_token" {
  name = "traefik-dns-01"

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.zone["DNS Write"],
      data.cloudflare_api_token_permission_groups.all.zone["Zone Read"],
    ]
    resources = {
      "com.cloudflare.api.account.zone.${var.cloudflare_zone_id}" = "*"
    }
  }
}

# Create the Cloudflare Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  secret     = base64encode(random_password.tunnel_secret.result)
}

# DNS Records for the tunnel
resource "cloudflare_record" "root_domain" {
  zone_id         = var.cloudflare_zone_id
  name            = var.domain_name
  content         = "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com"
  type            = "CNAME"
  proxied         = true
  allow_overwrite = true
}

resource "cloudflare_record" "wildcard_domain" {
  zone_id         = var.cloudflare_zone_id
  name            = "*"
  content         = "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com"
  type            = "CNAME"
  proxied         = true
  allow_overwrite = true
}

# Tunnel configuration for ingress rules
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id

  config {
    origin_request {
      no_tls_verify = true
    }

    ingress_rule {
      hostname = var.domain_name
      service  = "https://traefik:443"
    }

    ingress_rule {
      hostname = "*.${var.domain_name}"
      service  = "https://traefik:443"
    }

    # Catch-all rule
    ingress_rule {
      service = "http_status:404"
    }
  }
}
