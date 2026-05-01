resource "docker_network" "public" {
  name     = "public"
  internal = false
}

resource "docker_network" "proxy_cloudflare" {
  name     = "proxy-cloudflare"
  internal = true
}

resource "docker_network" "proxy_postgres" {
  name     = "proxy-postgres"
  internal = true
}

resource "docker_network" "proxy_authentik" {
  name     = "proxy-authentik"
  internal = true
}

resource "docker_network" "proxy_gatus" {
  name     = "proxy-gatus"
  internal = true
}

resource "docker_network" "proxy_homepage" {
  name     = "proxy-homepage"
  internal = true
}

resource "docker_network" "proxy_whoami" {
  name     = "proxy-whoami"
  internal = true
}

resource "docker_network" "proxy_capy" {
  name     = "proxy-capy"
  internal = true
}
