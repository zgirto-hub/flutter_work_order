#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./update_nginx_config.sh
#   ./update_nginx_config.sh --server user@host
#   ./update_nginx_config.sh --source /path/to/flutter_app.conf
#   ./update_nginx_config.sh --remote /etc/nginx/sites-available/flutter_app

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load deploy config from root .env
if [ -f "$ROOT/.env" ]; then
  set -a; source "$ROOT/.env"; set +a
fi
SERVER="${DEPLOY_SERVER:-zorin@100.85.73.37}"
SOURCE_FILE="$ROOT/server/nginx/flutter_app.conf"
REMOTE_TMP="/tmp/flutter_app"
REMOTE_TARGET="/etc/nginx/sites-available/flutter_app"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)
      SERVER="$2"
      shift 2
      ;;
    --source)
      SOURCE_FILE="$2"
      shift 2
      ;;
    --remote)
      REMOTE_TARGET="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Updates nginx site config on remote server.

Options:
  --server <user@host>   SSH target (default: zorin@100.85.73.37)
  --source <path>        Local config file (default: server/nginx/flutter_app.conf)
  --remote <path>        Remote config path (default: /etc/nginx/sites-available/flutter_app)
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run with --help for usage."
      exit 1
      ;;
  esac
done

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "Local config not found: $SOURCE_FILE"
  exit 1
fi

echo "Uploading nginx config to $SERVER:$REMOTE_TMP"
scp "$SOURCE_FILE" "$SERVER:$REMOTE_TMP"

echo "Installing config, testing nginx, reloading service"
ssh -t "$SERVER" "sudo install -m 644 '$REMOTE_TMP' '$REMOTE_TARGET' && sudo nginx -t && sudo systemctl reload nginx"

echo "Done. Active config: $REMOTE_TARGET"
