resource "docker_volume" "postgresql_data" {
  name = "postgresql_data"
}

resource "docker_volume" "authentik_data" {
  name = "authentik_data"
}

resource "docker_volume" "authentik_certs" {
  name = "authentik_certs"
}

resource "docker_volume" "authentik_custom_templates" {
  name = "authentik_custom_templates"
}

resource "docker_volume" "gatus_data" {
  name = "gatus_data"
}
