#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="$HOME/.openclaw"

require_env() {
  local var_name="$1"
  local var_value="${!var_name}"
  if [[ -z "$var_value" ]]; then
    echo "ERROR: $var_name is not set. Please export it before running this script." >&2
    echo "Required variables: TELEGRAM_BOT_TOKEN, ADMIN_TELEGRAM_USER_ID, ADMIN_EMAIL, OLLAMA_MODEL" >&2
    exit 1
  fi
}

install_node_if_needed() {
  if command -v node &>/dev/null; then
    local node_version
    node_version=$(node --version | sed 's/v//' | cut -d. -f1)
    if [[ "$node_version" -ge 20 ]]; then
      echo "Node.js $(node --version) is already installed."
      return
    fi
  fi
  
  echo "Node.js >=20 not found. Installing Node.js 20..."
  
  if command -v apt-get &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - || {
      echo "Failed to setup NodeSource. Trying alternative method..." >&2
      sudo apt-get update
      sudo apt-get install -y nodejs
    }
  else
    echo "apt-get not available. Please install Node.js 20+ manually." >&2
    exit 1
  fi
}

install_openclaw_if_needed() {
  if command -v openclaw &>/dev/null; then
    echo "OpenClaw is already installed: $(which openclaw)"
    return
  fi
  
  echo "Installing OpenClaw globally..."
  npm install -g openclaw || {
    echo "npm install failed. Trying alternative install method..." >&2
    echo "Please install openclaw manually: npm install -g openclaw" >&2
    exit 1
  }
}

render_config() {
  echo "Rendering OpenClaw configuration..."
  
  local token="${TELEGRAM_BOT_TOKEN}"
  local user_id="${ADMIN_TELEGRAM_USER_ID}"
  local email="${ADMIN_EMAIL}"
  local model="${OLLAMA_MODEL}"
  
  sed -e "s|__TELEGRAM_BOT_TOKEN__|$token|g" \
      -e "s|__ADMIN_TELEGRAM_USER_ID__|$user_id|g" \
      -e "s|__ADMIN_EMAIL__|$email|g" \
      -e "s|__OLLAMA_MODEL__|$model|g" \
      "$SCRIPT_DIR/openclaw.json.template" > "$OPENCLAW_DIR/openclaw.json"
  
  chmod 0600 "$OPENCLAW_DIR/openclaw.json"
  echo "Configuration written to $OPENCLAW_DIR/openclaw.json"
}

install_systemd_unit() {
  echo "Installing systemd unit..."
  
  if [[ ! -f "$SCRIPT_DIR/openclaw.service" ]]; then
    echo "ERROR: openclaw.service not found in $SCRIPT_DIR" >&2
    exit 1
  fi
  
  sudo cp "$SCRIPT_DIR/openclaw.service" /etc/systemd/system/openclaw.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now openclaw
  
  echo "OpenClaw service installed and started."
}

main() {
  echo "=== OpenClaw Installation Script ==="
  echo ""
  
  echo "Checking required environment variables..."
  require_env "TELEGRAM_BOT_TOKEN"
  require_env "ADMIN_TELEGRAM_USER_ID"
  require_env "ADMIN_EMAIL"
  require_env "OLLAMA_MODEL"
  echo "All required variables are set."
  echo ""
  
  echo "Checking Node.js version..."
  install_node_if_needed
  echo ""
  
  echo "Installing OpenClaw..."
  install_openclaw_if_needed
  echo ""
  
  echo "Creating OpenClaw directories..."
  mkdir -p "$OPENCLAW_DIR/skills"
  mkdir -p "$(dirname "$OPENCLAW_DIR/audit.log")"
  echo ""
  
  echo "Copying skills to OpenClaw directory..."
  cp -r "$SCRIPT_DIR/skills/"* "$OPENCLAW_DIR/skills/"
  echo ""
  
  echo "Creating audit log..."
  touch "$OPENCLAW_DIR/audit.log"
  chmod 0640 "$OPENCLAW_DIR/audit.log"
  echo ""
  
  echo "Rendering configuration..."
  render_config
  echo ""
  
  echo "Installing systemd unit..."
  install_systemd_unit
  echo ""
  
  echo "Checking service status..."
  if systemctl is-active --quiet openclaw; then
    echo ""
    echo "Waiting 5 seconds for service to initialize..."
    sleep 5
    echo ""
    echo "Recent journalctl output:"
    sudo journalctl -u openclaw -n 50 --no-pager || true
  else
    echo "WARNING: openclaw service may not have started correctly." >&2
    echo "Check status with: sudo systemctl status openclaw" >&2
  fi
  
  echo ""
  echo "========================================="
  echo -e "\033[0;32mOpenClaw installed and running.\033[0m"
  echo "========================================="
}

main "$@"