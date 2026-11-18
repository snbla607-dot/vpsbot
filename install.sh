#!/usr/bin/env bash
set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/snbla607-dot/vpsbot/main"
APP_DIR="/opt/sanity"
SERVICE="sanity"

info() { echo -e "\033[0;36m[Sanity]\033[0m $*"; }
fail() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }
[[ "$EUID" -eq 0 ]] || fail "Run as root: sudo bash install.sh"
command -v curl >/dev/null 2>&1 || { apt-get update; apt-get install -y curl; }

info "Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv python3-pip python3-dev build-essential libffi-dev libssl-dev ca-certificates curl

info "Preparing $APP_DIR..."
install -d -m 0750 "$APP_DIR"
for file in bot.py webssh.html .env.example; do
  curl -fL --retry 3 "$REPO_RAW/$file" -o "$APP_DIR/$file"
done

if [[ ! -f "$APP_DIR/.env" ]]; then
  cp "$APP_DIR/.env.example" "$APP_DIR/.env"
  chmod 0600 "$APP_DIR/.env"
  info "Created $APP_DIR/.env from .env.example"
else
  info "Existing .env preserved."
fi

if grep -q '^DISCORD_TOKEN=PASTE_YOUR_DISCORD_BOT_TOKEN_HERE$' "$APP_DIR/.env"; then
  echo
  info "Add your Discord bot token and IDs, then run this installer again:"
  echo "  nano $APP_DIR/.env"
  exit 0
fi
if ! grep -q '^MAIN_ADMIN_ID=[0-9]\{15,25\}$' "$APP_DIR/.env"; then
  fail "Set a valid MAIN_ADMIN_ID in $APP_DIR/.env first."
fi
sed -i 's/^BOT_NAME=.*/BOT_NAME=Sanity/' "$APP_DIR/.env"
chmod 0600 "$APP_DIR/.env"

info "Creating Python virtual environment..."
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/python" -m pip install --upgrade pip wheel
"$APP_DIR/venv/bin/pip" install discord.py python-dotenv PyNaCl argon2-cffi cryptography paramiko Flask flask-cors psutil aiohttp requests
"$APP_DIR/venv/bin/python" -m py_compile "$APP_DIR/bot.py"

if ! command -v lxc >/dev/null 2>&1; then
  info "WARNING: LXC/LXD CLI not found. Install and initialize LXD separately for container provisioning."
fi

cat > "/etc/systemd/system/$SERVICE.service" <<EOF
[Unit]
Description=Sanity VPS Management Bot
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
Environment=PYTHONUNBUFFERED=1
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/bot.py
Restart=on-failure
RestartSec=5
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "$SERVICE.service"
systemctl restart "$SERVICE.service"
sleep 2
systemctl --no-pager --full status "$SERVICE.service" || true

echo
echo "Sanity installation finished."
echo "Config: $APP_DIR/.env"
echo "Web SSH: $APP_DIR/webssh.html"
echo "Logs: journalctl -u sanity -f"
