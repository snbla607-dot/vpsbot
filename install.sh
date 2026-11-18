#!/usr/bin/env bash
set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/snbla607-dot/vpsbot/main"
APP_DIR="/opt/sanity"
SERVICE="sanity"

info() { echo -e "\033[0;36m[Sanity]\033[0m $*"; }
warn() { echo -e "\033[0;33m[Sanity]\033[0m $*"; }
fail() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }
prompt() {
  local var_name="$1" label="$2" default="${3:-}" value=""
  if [[ -n "$default" ]]; then
    read -r -p "$label [$default]: " value
    value="${value:-$default}"
  else
    read -r -p "$label: " value
  fi
  printf -v "$var_name" '%s' "$value"
}
prompt_secret() {
  local var_name="$1" label="$2" value=""
  while true; do
    read -r -s -p "$label: " value
    echo
    [[ -n "$value" ]] || { warn "This field is required."; continue; }
    [[ "$value" != *$'\n'* ]] || { warn "Newlines are not allowed."; continue; }
    printf -v "$var_name" '%s' "$value"
    return
  done
}
valid_snowflake() { [[ "$1" =~ ^[0-9]{15,25}$ ]]; }

[[ "$EUID" -eq 0 ]] || fail "Run as root: sudo bash install.sh"
command -v curl >/dev/null 2>&1 || { apt-get update; apt-get install -y curl; }

export DEBIAN_FRONTEND=noninteractive
info "Installing system dependencies..."
apt-get update
apt-get install -y python3 python3-venv python3-pip python3-dev build-essential libffi-dev libssl-dev ca-certificates curl

info "Downloading Sanity application files..."
install -d -m 0750 "$APP_DIR"
for file in bot.py webssh.html .env.example; do
  curl -fLsS --retry 3 "$REPO_RAW/$file" -o "$APP_DIR/$file" || fail "Could not download $file from the GitHub main branch."
done

if [[ ! -f "$APP_DIR/.env" ]]; then
  cp "$APP_DIR/.env.example" "$APP_DIR/.env"
  chmod 0600 "$APP_DIR/.env"
fi

echo
echo "=============================================="
echo "          SANITY FIRST-TIME SETUP"
echo "=============================================="
echo "Enter your Discord and VPS settings below."
echo "Your bot token is hidden while typing and is saved"
echo "only in $APP_DIR/.env (permissions 600)."
echo

while true; do
  prompt_secret DISCORD_TOKEN "Discord bot token"
  if [[ ${#DISCORD_TOKEN} -ge 50 ]]; then break; fi
  warn "That token looks too short. Copy the Bot Token from Discord Developer Portal."
done

while true; do
  prompt MAIN_ADMIN_ID "Main admin Discord User ID"
  valid_snowflake "$MAIN_ADMIN_ID" && break
  warn "Enter a valid Discord ID (15–25 digits). Enable Developer Mode to copy IDs."
done

prompt VPS_USER_ROLE_ID "VPS user role ID (leave blank to let Sanity create/manage its role)" ""
if [[ -n "$VPS_USER_ROLE_ID" ]] && ! valid_snowflake "$VPS_USER_ROLE_ID"; then
  fail "VPS user role ID must be 15–25 digits, or left blank."
fi

while true; do
  prompt YOUR_SERVER_IP "VPS public IP or public hostname" ""
  [[ -n "$YOUR_SERVER_IP" ]] && break
  warn "This is required for VPS connection details."
done

prompt PREFIX "Bot command prefix" "!"
prompt DEFAULT_STORAGE_POOL "LXD storage pool name" "default"
prompt BOT_DEVELOPER "Developer/credit name" "Sanity Team"
prompt WEBSSH_HOST "Web SSH bind address" "0.0.0.0"
while true; do
  prompt WEBSSH_PORT "Web SSH port" "5000"
  [[ "$WEBSSH_PORT" =~ ^[0-9]+$ ]] && (( WEBSSH_PORT >= 1 && WEBSSH_PORT <= 65535 )) && break
  warn "Enter a port between 1 and 65535."
done
prompt WEBSSH_SERVER_IP "Web SSH public IP or hostname" "$YOUR_SERVER_IP"
prompt WEBSSH_URL_FORMAT "Web SSH URL format" "http://{SERVER_IP}:{PORT}"
prompt OWNER_IDS "Extra owner Discord IDs (comma-separated, optional)" "$MAIN_ADMIN_ID"
while true; do
  read -r -p "Enable random PIN protection for new Web SSH links? [Y/n]: " answer
  case "${answer,,}" in
    ""|y|yes) WEBSSH_DEFAULT_PIN=true; break ;;
    n|no) WEBSSH_DEFAULT_PIN=false; break ;;
    *) warn "Please answer y or n." ;;
  esac
done

# Validate comma-separated owner IDs if supplied.
if [[ -n "$OWNER_IDS" ]]; then
  IFS=',' read -ra owner_array <<< "$OWNER_IDS"
  for owner_id in "${owner_array[@]}"; do
    owner_id="${owner_id//[[:space:]]/}"
    valid_snowflake "$owner_id" || fail "Invalid ID in OWNER_IDS: $owner_id"
  done
fi

export DISCORD_TOKEN MAIN_ADMIN_ID VPS_USER_ROLE_ID YOUR_SERVER_IP PREFIX
export DEFAULT_STORAGE_POOL BOT_DEVELOPER WEBSSH_HOST WEBSSH_PORT WEBSSH_SERVER_IP
export WEBSSH_URL_FORMAT OWNER_IDS WEBSSH_DEFAULT_PIN

info "Saving configuration..."
python3 - "$APP_DIR/.env" <<'PY'
import os, sys
from pathlib import Path

path = Path(sys.argv[1])
updates = {
    "DISCORD_TOKEN": os.environ["DISCORD_TOKEN"],
    "BOT_NAME": "Sanity",
    "MAIN_ADMIN_ID": os.environ["MAIN_ADMIN_ID"],
    "VPS_USER_ROLE_ID": os.environ.get("VPS_USER_ROLE_ID", ""),
    "YOUR_SERVER_IP": os.environ["YOUR_SERVER_IP"],
    "PREFIX": os.environ["PREFIX"],
    "DEFAULT_STORAGE_POOL": os.environ["DEFAULT_STORAGE_POOL"],
    "BOT_DEVELOPER": os.environ["BOT_DEVELOPER"],
    "WEBSSH_HOST": os.environ["WEBSSH_HOST"],
    "WEBSSH_PORT": os.environ["WEBSSH_PORT"],
    "WEBSSH_SERVER_IP": os.environ["WEBSSH_SERVER_IP"],
    "WEBSSH_URL_FORMAT": os.environ["WEBSSH_URL_FORMAT"],
    "OWNER_IDS": os.environ["OWNER_IDS"],
    "WEBSSH_DEFAULT_PIN": os.environ["WEBSSH_DEFAULT_PIN"],
}
lines = path.read_text().splitlines() if path.exists() else []
seen = set()
out = []
for line in lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in line:
        out.append(line)
        continue
    key = line.split("=", 1)[0].strip()
    if key in updates:
        out.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n")
path.chmod(0o600)
PY
unset DISCORD_TOKEN

info "Creating Python virtual environment..."
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/python" -m pip install --upgrade pip wheel
"$APP_DIR/venv/bin/pip" install discord.py python-dotenv PyNaCl argon2-cffi cryptography paramiko Flask flask-cors psutil aiohttp requests
"$APP_DIR/venv/bin/python" -m py_compile "$APP_DIR/bot.py"

if ! command -v lxc >/dev/null 2>&1; then
  warn "LXC/LXD CLI not found. Install and initialize LXD before using container provisioning features."
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

echo
echo "=============================================="
echo "          SANITY INSTALL COMPLETE"
echo "=============================================="
echo "Config:  $APP_DIR/.env"
echo "Web SSH: $APP_DIR/webssh.html"
echo "Status:  systemctl status sanity"
echo "Logs:    journalctl -u sanity -f"
echo
systemctl --no-pager --full status "$SERVICE.service" || true
