output "environment_files" {
  description = "A map of environment files to their respective variable sets"
  value = {
    "docker/core/postgresql/.env.postgresql" = {
      POSTGRES_USER               = "admin"
      POSTGRES_PASSWORD           = random_password.postgresql_admin.result
      POSTGRES_DB                 = "postgres"
      AUTHENTIK_POSTGRES_PASSWORD = random_password.authentik_db.result
      CAPY_POSTGRES_PASSWORD      = random_password.capy_db.result
    }
    "docker/core/authentik/.env.authentik" = {
      AUTHENTIK_POSTGRESQL__PASSWORD = random_password.authentik_db.result
      AUTHENTIK_SECRET_KEY           = random_password.authentik_secret_key.result
    }
    "docker/core/cloudflared/.env.cloudflared" = {
      TUNNEL_TOKEN = cloudflare_zero_trust_tunnel_cloudflared.main.tunnel_token
    }
    "docker/core/traefik/.env.traefik" = {
      CF_DNS_API_TOKEN = cloudflare_api_token.traefik_dns_token.value
    }
    "docker/capy/.env.capy" = {
      POSTGRES_USER     = "capy_user"
      POSTGRES_PASSWORD = random_password.capy_db.result
      POSTGRES_DB       = "capy_db"
      DATABASE_URL      = "postgres://capy_user:${random_password.capy_db.result}@postgresql:5432/capy_db?sslmode=disable"
      JWT_SECRET        = random_password.capy_jwt.result
    }
  }
  sensitive = true
}

output "tunnel_id" {
  description = "The ID of the Cloudflare Tunnel"
  value       = cloudflare_zero_trust_tunnel_cloudflared.main.id
}
