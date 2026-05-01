resource "random_password" "postgresql_admin" {
  length  = 32
  special = false
}

resource "random_password" "authentik_db" {
  length  = 32
  special = false
}

resource "random_password" "authentik_secret_key" {
  length  = 64
  special = false
}

resource "random_password" "capy_db" {
  length  = 32
  special = false
}

resource "random_password" "capy_jwt" {
  length  = 64
  special = false
}
