#!/usr/bin/env bash
set -euo pipefail

# One-shot installer for capy-lab on a fresh Ubuntu host.

REPO_URL="${REPO_URL:-https://github.com/CAPY-RPI/launch}"
CLONE_DIR="${CLONE_DIR:-$HOME/capy-lab}"

if [[ $EUID -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

export DEBIAN_FRONTEND=noninteractive

# --- System update + baseline tooling ----------------------------------------
$SUDO apt-get update
$SUDO apt-get -y upgrade
$SUDO apt-get install -y git make gpg

# --- Clone the repo if we're not already in it -------------------------------
# If we're already inside the checked-out repo, use that. Otherwise clone.
if [[ -f .env.example && -f docker-compose.yml ]]; then
  REPO_ROOT="$(pwd)"
else
  if [[ ! -d "$CLONE_DIR/.git" ]]; then
    git clone "$REPO_URL" "$CLONE_DIR"
  else
    echo "Using existing checkout at $CLONE_DIR"
  fi
  REPO_ROOT="$CLONE_DIR"
fi
cd "$REPO_ROOT"

# --- Docker (official apt repo) ----------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  $SUDO install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

  $SUDO apt-get update
  $SUDO apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  TARGET_USER="${SUDO_USER:-$USER}"
  if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
    $SUDO usermod -aG docker "$TARGET_USER"
  fi
fi

# --- Terraform (HashiCorp apt repo) ------------------------------------------
if ! command -v terraform >/dev/null 2>&1; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \
    $(lsb_release -cs) main" \
    | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

  $SUDO apt-get update
  $SUDO apt-get install -y terraform
fi

# --- uv (astral installer) ---------------------------------------------------
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  if [[ -f "$HOME/.local/bin/env" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.local/bin/env"
  else
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

# --- Copy .env.example -> .env if not present --------------------------------
ENV_FILE="$REPO_ROOT/.env"
if [[ -f "$REPO_ROOT/.env.example" && ! -f "$ENV_FILE" ]]; then
  cp "$REPO_ROOT/.env.example" "$ENV_FILE"
fi

echo
echo "Installed:"
docker --version || true
docker compose version || true
terraform --version || true
uv --version || true

# --- Guided .env configuration ----------------------------------------------

env_get() {
  awk -v k="$1" '
    BEGIN { FS="=" }
    $1 == k { sub(/^[^=]+=/, ""); print; exit }
  ' "$ENV_FILE"
}

env_set() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$value" '
    BEGIN { set = 0 }
    $0 ~ "^"k"=" { print k"="v; set = 1; next }
    { print }
    END { if (!set) print k"="v }
  ' "$ENV_FILE" > "$tmp"
  mv "$tmp" "$ENV_FILE"
}

ask() {
  # ask <var-to-set> <prompt> [default]
  local var="$1" label="$2" def="${3:-}" ans
  if [[ -n "$def" ]]; then
    read -rp "  $label [$def]: " ans </dev/tty
  else
    read -rp "  $label: " ans </dev/tty
  fi
  printf -v "$var" '%s' "${ans:-$def}"
}

ask_secret() {
  local var="$1" label="$2" def="${3:-}" ans
  if [[ -n "$def" ]]; then
    read -rsp "  $label [keep existing]: " ans </dev/tty
  else
    read -rsp "  $label: " ans </dev/tty
  fi
  echo
  printf -v "$var" '%s' "${ans:-$def}"
}

ask_yn() {
  local label="$1" def="${2:-N}" ans
  read -rp "  $label [y/N]: " ans </dev/tty
  ans="${ans:-$def}"
  [[ "$ans" =~ ^[Yy]$ ]]
}

if [[ -r /dev/tty ]]; then
  echo
  echo "Configure .env (press Enter to keep the value in brackets)"
  echo

  # --- Domain
  ask DOMAIN_NAME           "DOMAIN_NAME"           "$(env_get DOMAIN_NAME)"

  # --- Cloudflare
  ask_secret CF_TOKEN       "CLOUDFLARE_API_TOKEN"  "$(env_get CLOUDFLARE_API_TOKEN)"
  ask CF_ACCOUNT            "CLOUDFLARE_ACCOUNT_ID" "$(env_get CLOUDFLARE_ACCOUNT_ID)"
  ask CF_ZONE               "CLOUDFLARE_ZONE_ID"    "$(env_get CLOUDFLARE_ZONE_ID)"

  # --- Authentik bootstrap
  ask AK_EMAIL              "AUTHENTIK_BOOTSTRAP_EMAIL" \
                            "$(env_get AUTHENTIK_BOOTSTRAP_EMAIL || echo "admin@${DOMAIN_NAME}")"
  ask_secret AK_PASS        "AUTHENTIK_BOOTSTRAP_PASSWORD" "$(env_get AUTHENTIK_BOOTSTRAP_PASSWORD)"

  # --- Capy Google OAuth
  ask CAPY_GID              "CAPY_GOOGLE_CLIENT_ID"  "$(env_get CAPY_GOOGLE_CLIENT_ID)"
  ask_secret CAPY_GSEC      "CAPY_GOOGLE_CLIENT_SECRET" "$(env_get CAPY_GOOGLE_CLIENT_SECRET)"

  default_redirect="https://${DOMAIN_NAME}/api/v1/auth/google/callback"
  existing_redirect="$(env_get CAPY_GOOGLE_REDIRECT_URL)"
  ask CAPY_GREDIR           "CAPY_GOOGLE_REDIRECT_URL" "${existing_redirect:-$default_redirect}"

  # --- Optional SMTP for Authentik
  echo
  if ask_yn "Configure Authentik SMTP (for password resets / invites)?"; then
    ask        SMTP_HOST    "AUTHENTIK_EMAIL__HOST"     "$(env_get AUTHENTIK_EMAIL__HOST)"
    ask        SMTP_PORT    "AUTHENTIK_EMAIL__PORT"     "$(env_get AUTHENTIK_EMAIL__PORT || echo 587)"
    ask        SMTP_USER    "AUTHENTIK_EMAIL__USERNAME" "$(env_get AUTHENTIK_EMAIL__USERNAME)"
    ask_secret SMTP_PASS    "AUTHENTIK_EMAIL__PASSWORD" "$(env_get AUTHENTIK_EMAIL__PASSWORD)"
    ask        SMTP_TLS     "AUTHENTIK_EMAIL__USE_TLS"  "$(env_get AUTHENTIK_EMAIL__USE_TLS || echo true)"
    ask        SMTP_SSL     "AUTHENTIK_EMAIL__USE_SSL"  "$(env_get AUTHENTIK_EMAIL__USE_SSL || echo false)"
    ask        SMTP_FROM    "AUTHENTIK_EMAIL__FROM"     "$(env_get AUTHENTIK_EMAIL__FROM || echo "authentik@${DOMAIN_NAME}")"

    env_set AUTHENTIK_EMAIL__HOST     "$SMTP_HOST"
    env_set AUTHENTIK_EMAIL__PORT     "$SMTP_PORT"
    env_set AUTHENTIK_EMAIL__USERNAME "$SMTP_USER"
    env_set AUTHENTIK_EMAIL__PASSWORD "$SMTP_PASS"
    env_set AUTHENTIK_EMAIL__USE_TLS  "$SMTP_TLS"
    env_set AUTHENTIK_EMAIL__USE_SSL  "$SMTP_SSL"
    env_set AUTHENTIK_EMAIL__FROM     "$SMTP_FROM"
  fi

  env_set DOMAIN_NAME                  "$DOMAIN_NAME"
  env_set CLOUDFLARE_API_TOKEN         "$CF_TOKEN"
  env_set CLOUDFLARE_ACCOUNT_ID        "$CF_ACCOUNT"
  env_set CLOUDFLARE_ZONE_ID           "$CF_ZONE"
  env_set AUTHENTIK_BOOTSTRAP_EMAIL    "$AK_EMAIL"
  env_set AUTHENTIK_BOOTSTRAP_PASSWORD "$AK_PASS"
  env_set CAPY_GOOGLE_CLIENT_ID        "$CAPY_GID"
  env_set CAPY_GOOGLE_CLIENT_SECRET    "$CAPY_GSEC"
  env_set CAPY_GOOGLE_REDIRECT_URL     "$CAPY_GREDIR"

  echo
  echo ".env written: $ENV_FILE"
  echo
  echo "Starting the stack (terraform apply + docker compose up -d)..."
  # sg activates the docker group for this one subshell, so make run can talk
  # to the docker daemon without the user logging out and back in.
  sg docker -c "make run"

  cat <<EOF

Done. Visit https://${DOMAIN_NAME} in ~2 minutes
(Let's Encrypt DNS-01 needs ~90s + DNS propagation before HTTPS works).
EOF
else
  cat <<EOF

Non-interactive shell — skipping .env prompts and 'make run'.
Edit $ENV_FILE, then run:

  cd $REPO_ROOT
  newgrp docker
  make run
EOF
fi
