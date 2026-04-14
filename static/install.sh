#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
#  Konduktor install script
#  Supports: Ubuntu/Debian 22.04+, macOS 13+
#
#  Idempotent — safe to run multiple times.
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${GREEN}[info]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}── $* ──${NC}"; }

# =============================================================================
#  Error trap — print troubleshooting help on failure
# =============================================================================

_CURRENT_STEP="initialising"

on_error() {
  local exit_code=$?
  echo ""
  echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}${BOLD} Installation failed during: ${_CURRENT_STEP}${NC}"
  echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "  Troubleshooting tips:"
  echo ""
  echo "  1. Check the error message above for details."
  echo "  2. If a package install failed, try running:"
  if [[ "${OS:-}" == "ubuntu" ]]; then
    echo "       sudo apt-get update && sudo apt-get install -f"
  elif [[ "${OS:-}" == "macos" ]]; then
    echo "       brew update && brew doctor"
  fi
  echo "  3. If a permission error, ensure you have sudo access."
  echo "  4. If a network error, check your internet connection and try again."
  echo "  5. This script is idempotent — just re-run it after fixing the issue:"
  echo "       bash install.sh"
  echo ""
  echo "  For more help, see: https://github.com/yakkomajuri/konduktor-oss"
  echo ""
  exit "$exit_code"
}
trap on_error ERR

# =============================================================================
#  OS detection
# =============================================================================

_CURRENT_STEP="OS detection"

OS=""
if [[ "$OSTYPE" == darwin* ]]; then
  OS="macos"
elif grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
  OS="ubuntu"
else
  error "Unsupported OS. This script supports Ubuntu/Debian and macOS."
fi

info "Detected OS: $OS"

# Ensure interactive prompts work even when piped (curl | bash).
# When stdin is a pipe, `read` would get EOF. Open /dev/tty on fd 3 instead.
if [[ -t 0 ]]; then
  exec 3<&0   # stdin is already a terminal — just dup it
else
  exec 3</dev/tty
fi

# =============================================================================
#  Prerequisites — must be installed and authenticated before running
# =============================================================================

_CURRENT_STEP="prerequisite checks"

# git (needed before clone step)
if ! command -v git &>/dev/null; then
  echo ""
  echo -e "${RED}[error]${NC} git is not installed."
  echo ""
  echo "  Install git before running this script."
  echo ""
  exit 1
fi

# GitHub CLI
PREREQ_FAIL=false
if ! command -v gh &>/dev/null; then
  echo ""
  error_msg="GitHub CLI (gh) is not installed."
  PREREQ_FAIL=true
elif ! gh auth status &>/dev/null; then
  echo ""
  error_msg="GitHub CLI (gh) is installed but not authenticated."
  PREREQ_FAIL=true
fi

if [[ "$PREREQ_FAIL" == true ]]; then
  echo -e "${RED}[error]${NC} $error_msg"
  echo ""
  echo "  Install and authenticate gh before running this script:"
  echo "    https://cli.github.com/"
  echo ""
  echo "  Then run:  gh auth login"
  echo ""
  exit 1
fi
info "gh authenticated: $(gh auth status 2>&1 | grep 'account' | sed 's/.*account //' | cut -d' ' -f1)"

# Claude Code
if ! command -v claude &>/dev/null; then
  echo ""
  echo -e "${RED}[error]${NC} Claude Code is not installed."
  echo ""
  echo "  Install and authenticate Claude Code before running this script:"
  echo "    https://code.claude.com/docs/en/quickstart"
  echo ""
  exit 1
fi
info "Claude Code installed: $(claude --version 2>/dev/null || echo 'yes')"

# =============================================================================
#  Clone repo if running standalone (e.g. curl | bash)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}" 2>/dev/null)" 2>/dev/null && pwd)" || true
INSTALL_DIR="${KONDUKTOR_INSTALL_DIR:-$HOME/konduktor-oss}"

if [[ -z "$SCRIPT_DIR" ]] || [[ ! -f "$SCRIPT_DIR/pyproject.toml" ]]; then
  _CURRENT_STEP="cloning repository"
  section "Cloning Konduktor"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Existing clone found at ${INSTALL_DIR} — pulling latest…"
    git -C "$INSTALL_DIR" pull --ff-only
  else
    info "Cloning konduktor-oss to ${INSTALL_DIR}…"
    git clone https://github.com/yakkomajuri/konduktor-oss.git "$INSTALL_DIR"
  fi
  exec "$INSTALL_DIR/install.sh"
fi

REPO_DIR="$SCRIPT_DIR"

# =============================================================================
#  Shell rc file
# =============================================================================

SHELL_RC="$HOME/.bashrc"
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$(basename "${SHELL:-}")" == "zsh" ]]; then
  SHELL_RC="$HOME/.zshrc"
elif [[ "$OS" == "macos" ]]; then
  # macOS default shell is zsh since Catalina
  SHELL_RC="$HOME/.zshrc"
fi

# Read a secret with ****** feedback (one * per character)
read_secret() {
  local prompt="$1" secret="" char=""
  printf "%s" "$prompt"
  while IFS= read -rsn1 char <&3; do
    [[ "$char" == $'\0' || "$char" == $'\n' ]] && break
    if [[ "$char" == $'\x7f' || "$char" == $'\b' ]]; then
      if [[ -n "$secret" ]]; then
        secret="${secret%?}"
        printf '\b \b'
      fi
    else
      secret+="$char"
      printf '*'
    fi
  done
  echo ""
  REPLY="$secret"
}

append_export() {
  local key="$1" value="$2"
  if ! grep -q "^export ${key}=" "$SHELL_RC" 2>/dev/null; then
    echo "export ${key}=\"${value}\"" >> "$SHELL_RC"
  else
    sed -i'' -e "s|^export ${key}=.*|export ${key}=\"${value}\"|" "$SHELL_RC"
  fi
  export "${key}=${value}"
}

prepend_path() {
  local dir="$1"
  if ! grep -q "${dir}" "$SHELL_RC" 2>/dev/null; then
    echo "export PATH=\"${dir}:\$PATH\"" >> "$SHELL_RC"
  fi
  export PATH="${dir}:${PATH}"
}

# Check if we can use sudo (needed for package install & systemd)
can_sudo() {
  if [[ "$EUID" -eq 0 ]]; then
    return 0
  fi
  if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
    return 0
  fi
  # sudo exists but may prompt — that's OK for interactive install
  if command -v sudo &>/dev/null; then
    return 0
  fi
  return 1
}

# =============================================================================
#  Collect all user input upfront so the rest of the script is non-interactive
# =============================================================================

SETUP_NGINX=false
SETUP_DOMAIN=false
DOMAIN_NAME=""
PUBLIC_IP=""
KONDUKTOR_USERNAME=""
KONDUKTOR_PASSWORD=""

CREDENTIALS_FILE="$HOME/.konduktor/credentials"
NEED_CREDENTIALS=true
if [[ -f "$CREDENTIALS_FILE" ]]; then
  NEED_CREDENTIALS=false
fi

echo ""
echo -e "${BOLD}${CYAN}── Configuration ──${NC}"
echo ""

# Credentials (only if not already set up)
if $NEED_CREDENTIALS; then
  info "Konduktor server credentials:"
  read -rp "  Username [admin]: " KONDUKTOR_USERNAME <&3
  KONDUKTOR_USERNAME="${KONDUKTOR_USERNAME:-admin}"
  read_secret "  Password: "
  KONDUKTOR_PASSWORD="$REPLY"
  if [[ -z "$KONDUKTOR_PASSWORD" ]]; then
    error "Password cannot be empty."
  fi
  echo ""
fi

# Reverse proxy (Linux only)
if [[ "$OS" == "ubuntu" ]]; then
  # Detect existing nginx setup for konduktor
  if [[ -f /etc/nginx/sites-available/konduktor ]]; then
    SETUP_NGINX=true
    # Extract domain from existing config
    EXISTING_SERVER_NAME=$(grep -oP 'server_name\s+\K[^;]+' /etc/nginx/sites-available/konduktor 2>/dev/null | head -1 || true)
    if [[ -n "$EXISTING_SERVER_NAME" && "$EXISTING_SERVER_NAME" != "_" ]]; then
      SETUP_DOMAIN=true
      DOMAIN_NAME="$EXISTING_SERVER_NAME"
    fi
    PUBLIC_IP=$(curl -4 -sf https://ifconfig.me || curl -4 -sf https://api.ipify.org || echo "")
    info "Existing nginx config detected — skipping proxy setup prompts."
  else
    read -rp "  Configure nginx as a reverse proxy? (recommended) [Y/n]: " nginx_choice <&3
    if [[ "${nginx_choice:-Y}" =~ ^[Yy]$ ]]; then
      SETUP_NGINX=true

      PUBLIC_IP=$(curl -4 -sf https://ifconfig.me || curl -4 -sf https://api.ipify.org || echo "")

      read -rp "  Configure a domain with HTTPS? (recommended) [Y/n]: " domain_choice <&3
      if [[ "${domain_choice:-Y}" =~ ^[Yy]$ ]]; then
        SETUP_DOMAIN=true
        read -rp "  Domain name (e.g. konduktor.example.com): " DOMAIN_NAME <&3
        if [[ -z "$DOMAIN_NAME" ]]; then
          error "Domain name cannot be empty."
        fi

      echo ""
      echo -e "  ${BOLD}Point a DNS A record to this machine:${NC}"
      echo ""
      echo -e "    ${CYAN}${DOMAIN_NAME}${NC}  →  ${CYAN}${PUBLIC_IP}${NC}"
      echo ""
      echo "  Do this in your DNS provider (Cloudflare, Route 53, etc.) now."
      echo ""
      echo "  Note: if using Cloudflare, keep proxying disabled (DNS only / grey cloud)"
      echo "  for now to permit certificate provisioning. You can enable it later."
      echo ""
      # Ensure dig is available for DNS checking
      if ! command -v dig &>/dev/null; then
        sudo apt-get install -y -qq dnsutils 2>/dev/null || true
      fi

      info "Waiting for DNS to resolve…  (press 's' to skip)"
      echo ""

      DNS_RESOLVED=false
      DNS_WAIT=10
      DNS_ATTEMPT=0
      while true; do
        DNS_ATTEMPT=$((DNS_ATTEMPT + 1))
        DIG_OUTPUT=$(dig "$DOMAIN_NAME" A +noall +answer 2>/dev/null || true)
        RESOLVED_IP=$(echo "$DIG_OUTPUT" | awk '/\sA\s/{print $NF}' | tail -1)

        if [[ "$RESOLVED_IP" == "$PUBLIC_IP" ]]; then
          DNS_RESOLVED=true
          echo ""
          info "DNS verified — ${DOMAIN_NAME} resolves to ${PUBLIC_IP}"
          break
        fi

        echo -e "  ${BOLD}[check #${DNS_ATTEMPT}]${NC} dig ${DOMAIN_NAME} A"
        if [[ -n "$DIG_OUTPUT" ]]; then
          echo "$DIG_OUTPUT" | sed 's/^/    /'
        else
          echo "    (no answer)"
        fi
        if [[ -n "$RESOLVED_IP" ]]; then
          echo -e "    ${YELLOW}→ Got ${RESOLVED_IP}, expected ${PUBLIC_IP}${NC}"
        else
          echo -e "    ${YELLOW}→ No A record found yet${NC}"
        fi

        # Countdown with 's' to skip
        for ((i=DNS_WAIT; i>0; i--)); do
          printf "\r\033[K  Next check in ${i}s  (press 's' to skip)"
          if read -rsn1 -t 1 key <&3 2>/dev/null && [[ "$key" == "s" ]]; then
            printf "\r\033[K"
            read -rp "  DNS hasn't resolved yet. Continue anyway? [y/N]: " skip_confirm <&3
            if [[ "${skip_confirm:-N}" =~ ^[Yy]$ ]]; then
              warn "Skipping DNS check — certbot may fail if DNS isn't ready."
              break 2
            fi
            break
          fi
        done
        printf "\r\033[K"
      done
      echo ""
    else
      info "Skipping domain — nginx will serve on http://${PUBLIC_IP:-<public-ip>}"
    fi
    else
      info "Skipping nginx setup."
    fi
  fi
fi

echo ""
info "Configuration complete. Installing…"

# =============================================================================
#  1. Python 3.11+
# =============================================================================

_CURRENT_STEP="Python installation"
section "1/10  Python 3.11+"

PYTHON_BIN=""
for candidate in python3.20 python3.19 python3.18 python3.17 python3.16 python3.15 python3.14 python3.13 python3.12 python3.11 python3; do
  if command -v "$candidate" &>/dev/null; then
    ver=$("$candidate" -c 'import sys; print(sys.version_info[:2])' 2>/dev/null || true)
    major=$(echo "$ver" | tr -d '()' | cut -d',' -f1 | tr -d ' ')
    minor=$(echo "$ver" | tr -d '()' | cut -d',' -f2 | tr -d ' ')
    if [[ "$major" -ge 3 && "$minor" -ge 11 ]]; then
      PYTHON_BIN="$candidate"
      break
    fi
  fi
done

if [[ -n "$PYTHON_BIN" ]]; then
  info "Python already available: $($PYTHON_BIN --version)"
else
  info "Installing Python 3.11…"
  if [[ "$OS" == "ubuntu" ]]; then
    sudo apt-get install -y -qq software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3.11 python3.11-venv python3.11-dev
    PYTHON_BIN="python3.11"
  else
    brew install python@3.11
    PYTHON_BIN="$(brew --prefix python@3.11)/bin/python3.11"
    prepend_path "$(brew --prefix python@3.11)/bin"
  fi
  info "Python installed: $($PYTHON_BIN --version)"
fi

# =============================================================================
#  2. uv
# =============================================================================

_CURRENT_STEP="uv installation"
section "2/10  uv"
if command -v uv &>/dev/null; then
  info "uv already installed: $(uv --version)"
else
  info "Installing uv…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # Source uv's env file to get it on PATH for the rest of this script
  for env_file in "$HOME/.local/bin/env" "$HOME/.cargo/env"; do
    if [[ -f "$env_file" ]]; then
      source "$env_file"
      break
    fi
  done
  info "uv installed: $(uv --version)"
fi

# =============================================================================
#  3. Node.js 22+ (required for the CLI)
# =============================================================================

_CURRENT_STEP="Node.js installation"
section "3/10  Node.js"
NEED_NODE=true
if command -v node &>/dev/null; then
  NODE_MAJOR=$(node -v | sed 's/v\([0-9]*\).*/\1/')
  if [[ "$NODE_MAJOR" -ge 22 ]]; then
    NEED_NODE=false
    info "Node.js already installed: $(node -v)"
  else
    warn "Node.js $(node -v) is too old (need ≥22). Upgrading…"
  fi
fi

if $NEED_NODE; then
  if [[ "$OS" == "ubuntu" ]]; then
    info "Installing Node.js 24.x…"
    sudo apt-get install -y -qq ca-certificates curl gnupg
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
      | sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null
    sudo apt-get update -qq -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/nodesource.list -o Dir::Etc::sourceparts=/dev/null && sudo apt-get install -y -qq nodejs
  else
    brew install node
  fi
  info "Node.js installed: $(node -v)"
fi

# =============================================================================
#  4. pnpm
# =============================================================================

_CURRENT_STEP="pnpm installation"
section "4/10  pnpm"
export PNPM_HOME="$HOME/.local/share/pnpm"
mkdir -p "$PNPM_HOME"
prepend_path "$PNPM_HOME"
if command -v pnpm &>/dev/null; then
  info "pnpm already installed: $(pnpm --version)"
else
  info "Installing pnpm…"
  curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME="$PNPM_HOME" sh -
  info "pnpm installed: $(pnpm --version)"
fi

# =============================================================================
#  5. Konduktor server (Python package)
# =============================================================================

_CURRENT_STEP="Konduktor server installation"
section "5/10  Konduktor server"
info "Installing konduktor from ${REPO_DIR}…"
(cd "$REPO_DIR" && uv sync)
uv tool install --force --from "$REPO_DIR" konduktor
prepend_path "$HOME/.local/bin"
info "konduktor-server installed: $(konduktor-server --help 2>&1 | head -1 || true)"

# =============================================================================
#  6. Konduktor CLI (TypeScript)
# =============================================================================

_CURRENT_STEP="Konduktor CLI build"
section "6/10  Konduktor CLI"
CLI_DIR="${REPO_DIR}/cli"
info "Building CLI…"
(cd "$CLI_DIR" && pnpm install --silent && pnpm run generate && pnpm run build)
# Symlink the CLI binary onto PATH
chmod +x "${CLI_DIR}/dist/index.js"
ln -sf "${CLI_DIR}/dist/index.js" "$HOME/.local/bin/konduktor"
info "konduktor CLI installed: $(konduktor --version 2>/dev/null || true)"

# =============================================================================
#  7. Konduktor UI (Vite + React)
# =============================================================================

_CURRENT_STEP="Konduktor UI build"
section "7/10  Konduktor UI"
UI_DIR="${REPO_DIR}/ui"
info "Building UI…"
(cd "$UI_DIR" && pnpm install --silent && pnpm run build)
info "UI built: ${UI_DIR}/dist"


# =============================================================================
#  8. Server initialisation
# =============================================================================

_CURRENT_STEP="server initialisation"
section "8/10  Konduktor server setup"

if [[ -f "$CREDENTIALS_FILE" ]]; then
  info "Existing server credentials found — skipping init."
  info "Running database migrations…"
  (cd "$REPO_DIR" && uv run konduktor-server upgrade)
else
  (cd "$REPO_DIR" && uv run konduktor-server init --username "$KONDUKTOR_USERNAME" --password "$KONDUKTOR_PASSWORD")
fi

# =============================================================================
#  9. Systemd service (Linux only)
# =============================================================================

_CURRENT_STEP="systemd service setup"
section "9/10  Systemd service"

SYSTEMD_INSTALLED=false

if [[ "$OS" == "ubuntu" ]]; then
  if ! can_sudo; then
    warn "No sudo access — skipping systemd service setup."
    warn "You can start the server manually: konduktor-server start"
  else
    KONDUKTOR_SERVER_BIN="$(command -v konduktor-server 2>/dev/null || echo "$HOME/.local/bin/konduktor-server")"
    KONDUKTOR_USER="$(whoami)"
    KONDUKTOR_HOME="$HOME"

    # Compute external URL for public-facing links (PR descriptions, etc.)
    EXTERNAL_URL=""
    if [[ "$SETUP_DOMAIN" == true && -n "$DOMAIN_NAME" ]]; then
      EXTERNAL_URL="https://${DOMAIN_NAME}"
    elif [[ "$SETUP_NGINX" == true && -n "$PUBLIC_IP" ]]; then
      EXTERNAL_URL="http://${PUBLIC_IP}"
    fi

    info "Creating systemd service at /etc/systemd/system/konduktor.service…"

    sudo tee /etc/systemd/system/konduktor.service >/dev/null <<UNITEOF
[Unit]
Description=Konduktor Agent Control Plane
Documentation=https://github.com/yakkomajuri/konduktor-oss
After=network.target

[Service]
Type=simple
User=${KONDUKTOR_USER}
Group=${KONDUKTOR_USER}
WorkingDirectory=${REPO_DIR}
Environment=HOME=${KONDUKTOR_HOME}
Environment=PATH=${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin
${EXTERNAL_URL:+Environment=KONDUKTOR_EXTERNAL_URL=${EXTERNAL_URL}}
Environment=KONDUKTOR_UI_DIR=${REPO_DIR}/ui/dist
ExecStart=${KONDUKTOR_SERVER_BIN} start --host 127.0.0.1 --port 8080
Restart=on-failure
RestartSec=5
KillMode=process
StandardOutput=journal
StandardError=journal
SyslogIdentifier=konduktor

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=${KONDUKTOR_HOME}/.konduktor ${KONDUKTOR_HOME}/.claude ${KONDUKTOR_HOME}/.local ${KONDUKTOR_HOME}/.cache /tmp

[Install]
WantedBy=multi-user.target
UNITEOF

    sudo systemctl daemon-reload
    sudo systemctl enable konduktor.service
    info "Systemd service enabled."

    # Start or restart the service
    if sudo systemctl is-active --quiet konduktor.service 2>/dev/null; then
      info "Service already running — restarting to pick up changes…"
      sudo systemctl restart konduktor.service
    else
      info "Starting Konduktor service…"
      sudo systemctl start konduktor.service
    fi

    # Give the service a moment to start, then check status
    sleep 2
    if sudo systemctl is-active --quiet konduktor.service 2>/dev/null; then
      info "Konduktor service is running."
      SYSTEMD_INSTALLED=true

      # Auto-login the CLI
      if konduktor status &>/dev/null; then
        info "CLI already authenticated."
      elif [[ -n "${KONDUKTOR_USERNAME:-}" && -n "${KONDUKTOR_PASSWORD:-}" ]]; then
        info "Logging in to Konduktor CLI…"
        konduktor auth login --username "$KONDUKTOR_USERNAME" --password "$KONDUKTOR_PASSWORD" && \
          info "CLI authenticated as '${KONDUKTOR_USERNAME}'." || \
          warn "CLI login failed — run manually: konduktor auth login"
      else
        warn "CLI not authenticated. Log in with:"
        warn "  konduktor auth login --username <user> --password <pass>"
      fi
    else
      warn "Service started but may not be healthy yet. Check with:"
      warn "  sudo systemctl status konduktor"
      warn "  sudo journalctl -u konduktor -f"
      SYSTEMD_INSTALLED=true
    fi
  fi
elif [[ "$OS" == "macos" ]]; then
  info "Systemd is not available on macOS."
  info "Start the server manually with: konduktor-server start"
  info "Tip: you can use 'launchctl' to set up a launch agent if you want auto-start."
fi

# =============================================================================
#  10. Nginx & HTTPS (Linux only)
# =============================================================================

if [[ "$SETUP_NGINX" == true ]]; then
  _CURRENT_STEP="nginx setup"
  section "10/10  Nginx & HTTPS"

  if command -v nginx &>/dev/null && [[ -f /etc/nginx/sites-enabled/konduktor ]]; then
    info "nginx already configured for konduktor — skipping."
  else
    info "Installing nginx…"
    sudo apt-get update -qq || true
    sudo apt-get install -y -qq nginx

    # Determine server_name for nginx config
    if [[ "$SETUP_DOMAIN" == true ]]; then
      NGINX_SERVER_NAME="$DOMAIN_NAME"
    else
      NGINX_SERVER_NAME="_"
    fi

    info "Writing nginx config…"
    sudo tee /etc/nginx/sites-available/konduktor >/dev/null <<NGINXEOF
server {
    listen 80;
    server_name ${NGINX_SERVER_NAME};

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINXEOF

    sudo rm -f /etc/nginx/sites-enabled/default
    sudo ln -sf /etc/nginx/sites-available/konduktor /etc/nginx/sites-enabled/konduktor
    sudo nginx -t
    sudo systemctl enable nginx
    sudo systemctl restart nginx
    info "nginx is running."
  fi

  # Certbot for HTTPS
  if [[ "$SETUP_DOMAIN" == true ]]; then
    if sudo test -f "/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem"; then
      info "HTTPS certificate already exists for ${DOMAIN_NAME} — skipping."
    else
      info "Installing certbot…"
      sudo apt-get install -y -qq certbot python3-certbot-nginx

      info "Requesting HTTPS certificate for ${DOMAIN_NAME}…"
      if sudo certbot --nginx --non-interactive --agree-tos \
           --register-unsafely-without-email --redirect \
           -d "$DOMAIN_NAME"; then
        info "HTTPS configured for ${DOMAIN_NAME}."
      else
        warn "Certbot failed — DNS may not have propagated yet."
        warn "Run this manually once DNS is ready:"
        warn "  sudo certbot --nginx -d ${DOMAIN_NAME}"
      fi
    fi
  fi
fi

# =============================================================================
#  Done!
# =============================================================================

echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  Konduktor installed successfully!${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Installed components:${NC}"
echo "    python           $($PYTHON_BIN --version)"
echo "    uv               $(uv --version)"
echo "    node             $(node -v)"
echo "    pnpm             $(pnpm --version)"
echo "    konduktor-server $(konduktor-server --help 2>&1 | head -1 || echo 'installed')"
echo "    konduktor CLI    $(konduktor --version 2>/dev/null || echo 'installed')"
echo ""

if $SYSTEMD_INSTALLED; then
  echo -e "  ${BOLD}Server status:${NC}"
  if [[ "$SETUP_DOMAIN" == true ]]; then
    echo -e "    ${GREEN}●${NC} Konduktor is running at https://${DOMAIN_NAME}"
  elif [[ "$SETUP_NGINX" == true && -n "$PUBLIC_IP" ]]; then
    echo -e "    ${GREEN}●${NC} Konduktor is running at http://${PUBLIC_IP}"
  else
    echo -e "    ${GREEN}●${NC} Konduktor is running as a systemd service on http://127.0.0.1:8080"
  fi
  echo ""
  echo -e "  ${BOLD}Useful commands:${NC}"
  echo "    sudo systemctl status konduktor     # check status"
  echo "    sudo systemctl restart konduktor    # restart"
  echo "    sudo systemctl stop konduktor       # stop"
  echo "    sudo journalctl -u konduktor -f     # view logs"
  if [[ "$SETUP_NGINX" == true ]]; then
    echo "    sudo systemctl status nginx         # check nginx"
  fi
  if [[ "$SETUP_DOMAIN" == true ]]; then
    echo "    sudo certbot renew --dry-run        # test cert renewal"
  fi
  echo ""
fi

echo -e "  ${BOLD}Next steps:${NC}"
echo ""

if ! $SYSTEMD_INSTALLED; then
  echo -e "    ${CYAN}1. Start the server${NC}"
  echo "       konduktor-server start"
  echo ""
  echo -e "    ${CYAN}2. Log in (in a new terminal)${NC}"
  echo "       konduktor auth login --username <user> --password <pass>"
  echo ""
  echo -e "    ${CYAN}3. Add a workspace${NC}"
else
  echo -e "    ${CYAN}1. Add a workspace${NC}"
fi
echo "       konduktor workspaces add org/repo               # clone from GitHub"
echo "       konduktor workspaces add --local /path/to/repo  # local repo"
echo ""
if ! $SYSTEMD_INSTALLED; then
  echo -e "    ${CYAN}4. Create and run a task${NC}"
else
  echo -e "    ${CYAN}2. Create and run a task${NC}"
fi
echo "       konduktor tasks create <workspace> --title \"My first task\""
echo "       konduktor tasks run <workspace> <task-id>"
echo ""

if [[ "$SETUP_DOMAIN" == true ]]; then
  echo -e "  ${BOLD}GitHub webhook URL:${NC}"
  echo "    https://${DOMAIN_NAME}/api/github/webhook"
  echo ""
elif [[ "$SETUP_NGINX" == true ]]; then
  echo -e "  ${BOLD}GitHub webhook URL:${NC}"
  echo "    http://${PUBLIC_IP}/api/github/webhook"
  echo ""
else
  echo -e "  ${BOLD}Webhook / tunnel setup (optional):${NC}"
  echo ""
  echo "    If you want GitHub webhooks to trigger task updates, you need to expose"
  echo "    the Konduktor server to the internet. Options:"
  echo ""
  echo "      a) Use a reverse tunnel (easiest for development):"
  echo "         - cloudflared: cloudflared tunnel --url http://localhost:8080"
  echo "         - ngrok:       ngrok http 8080"
  echo ""
  echo "      b) Deploy behind a reverse proxy (Caddy, nginx) with a domain + TLS."
  echo ""
  echo "    Then set your GitHub App's webhook URL to:"
  echo "      https://<your-domain>/api/github/webhook"
  echo ""
fi

echo "  Tip: run 'source ${SHELL_RC}' or open a new terminal if PATH changes aren't active yet."
echo ""
