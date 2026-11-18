#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="SANITY"
APP_DIR="/opt/sanity"
SERVICE="sanity"
REPO_RAW="https://raw.githubusercontent.com/snbla607-dot/vpsbot/main"
DIALOG_TITLE="SANITY VPS MANAGER"
CONFIG_TMP="$(mktemp)"
trap 'rm -f "$CONFIG_TMP"' EXIT

# ---------- UI helpers ----------
if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root: sudo bash install.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
command -v curl >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y curl; }

# whiptail gives the installer a polished full-screen terminal GUI.
apt-get update -qq
apt-get install -y whiptail curl ca-certificates

ui_msg() {
  whiptail --title "$DIALOG_TITLE" --backtitle "SANITY  •  VPS MANAGEMENT PLATFORM" \
    --msgbox "$1" 12 72
}
ui_input() {
  local title="$1" prompt="$2" default="${3:-}" result
  result="$(whiptail --title "$DIALOG_TITLE" --backtitle "SANITY  •  CONFIGURATION WIZARD" \
    --inputbox "$prompt" 11 72 "$default" 3>&1 1>&2 2>&3)" || return 1
  printf '%s' "$result"
}
ui_password() {
  local prompt="$1" result
  result="$(whiptail --title "$DIALOG_TITLE" --backtitle "SANITY  •  SECURE CREDENTIALS" \
    --passwordbox "$prompt" 11 72 3>&1 1>&2 2>&3)" || return 1
  printf '%s' "$result"
}
ui_yesno() {
  whiptail --title "$DIALOG_TITLE" --backtitle "SANITY  •  CONFIGURATION WIZARD" \
    --yesno "$1" 10 72
}
ui_gauge() {
  local message="$1" percent="$2"
  printf '%s\n' "$percent" | whiptail --title "$DIALOG_TITLE" \
    --backtitle "SANITY  •  INSTALLATION" --gauge "$message" 8 72 0
}
fail_ui() {
  whiptail --title "INSTALLATION FAILED" --msgbox "$1" 10 72 || true
  exit 1
}
valid_id() { [[ "$1" =~ ^[0-9]{15,25}$ ]]; }
valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }

# Must be run from a real interactive terminal.
[[ -t 0 && -t 1 ]] || {
  echo "Sanity's graphical terminal installer needs an interactive SSH/terminal session."
  echo "Run: bash <(curl -fsSL https://raw.githubusercontent.com/snbla607-dot/vpsbot/main/install.sh)"
  exit 1
}

whiptail --title "$DIALOG_TITLE" --backtitle "SANITY  •  VPS MANAGEMENT PLATFORM" \
  --yesno "Welcome to Sanity.\n\nThis guided installer will configure your Discord bot, VPS host, Web SSH settings, Python environment and systemd service.\n\nYour Discord token is entered in a hidden password field and saved locally with restricted permissions.\n\nContinue?" 16 72 || exit 0

# ---------- Download application ----------
mkdir -p "$APP_DIR"
ui_gauge "Preparing installer and downloading Sanity files..." 5
for file in bot.py webssh.html .env.example; do
  curl -fLsS --retry 3 "$REPO_RAW/$file" -o "$APP_DIR/$file" || \
    fail_ui "Could not download $file.\n\nCheck that the file exists in the repository's main branch:\n$REPO_RAW/$file"
done

if [[ ! -f "$APP_DIR/.env" ]]; then
  cp "$APP_DIR/.env.example" "$APP_DIR/.env"
fi
chmod 600 "$APP_DIR/.env"

# ---------- Wizard: Discord ----------
while true; do
  DISCORD_TOKEN="$(ui_password "Step 1 of 4  •  Discord Bot Token\n\nPaste your bot token. Input is hidden.")" || exit 0
  [[ -n "$DISCORD_TOKEN" ]] || { ui_msg "Bot token cannot be empty."; continue; }
  break
done

while true; do
  MAIN_ADMIN_ID="$(ui_input "Step 1 of 4  •  Main Administrator" \
    "Enter your Discord User ID (15–25 digits):" "${MAIN_ADMIN_ID:-}")" || exit 0
  valid_id "$MAIN_ADMIN_ID" && break
  ui_msg "That Discord ID does not look valid.\n\nEnable Developer Mode in Discord, then use Copy User ID."
done

VPS_USER_ROLE_ID="$(ui_input "Step 1 of 4  •  VPS Member Role" \
  "Optional: enter the Discord role ID for VPS users.\nLeave blank if you do not have one:" "${VPS_USER_ROLE_ID:-}")" || exit 0
if [[ -n "$VPS_USER_ROLE_ID" ]] && ! valid_id "$VPS_USER_ROLE_ID"; then
  ui_msg "Role ID must contain 15–25 digits, or be left blank."
  VPS_USER_ROLE_ID=""
fi

# ---------- Wizard: host ----------
while true; do
  YOUR_SERVER_IP="$(ui_input "Step 2 of 4  •  VPS Host" \
    "Enter this VPS server's public IP address or public hostname:" "${YOUR_SERVER_IP:-}")" || exit 0
  [[ -n "$YOUR_SERVER_IP" ]] && break
  ui_msg "The VPS host/IP is required."
done

PREFIX="$(ui_input "Step 2 of 4  •  Bot Prefix" \
  "Choose the bot command prefix:" "${PREFIX:-!}")" || exit 0
[[ -n "$PREFIX" ]] || PREFIX="!"

DEFAULT_STORAGE_POOL="$(ui_input "Step 2 of 4  •  LXD Storage" \
  "Enter the existing LXD storage pool name:" "${DEFAULT_STORAGE_POOL:-default}")" || exit 0
[[ -n "$DEFAULT_STORAGE_POOL" ]] || DEFAULT_STORAGE_POOL="default"

BOT_DEVELOPER="$(ui_input "Step 2 of 4  •  Credits" \
  "Developer/team display name:" "${BOT_DEVELOPER:-Sanity Team}")" || exit 0
[[ -n "$BOT_DEVELOPER" ]] || BOT_DEVELOPER="Sanity Team"

# ---------- Wizard: Web SSH ----------
WEBSSH_HOST="$(ui_input "Step 3 of 4  •  Web SSH Binding" \
  "Address Web SSH should listen on.\nUse 0.0.0.0 to listen on all interfaces:" "${WEBSSH_HOST:-0.0.0.0}")" || exit 0
[[ -n "$WEBSSH_HOST" ]] || WEBSSH_HOST="0.0.0.0"

while true; do
  WEBSSH_PORT="$(ui_input "Step 3 of 4  •  Web SSH Port" \
    "Choose the local Web SSH listening port:" "${WEBSSH_PORT:-5000}")" || exit 0
  valid_port "$WEBSSH_PORT" && break
  ui_msg "Enter a valid TCP port from 1 to 65535."
done

WEBSSH_SERVER_IP="$(ui_input "Step 3 of 4  •  Web SSH Public Host" \
  "Public IP or hostname users will use to reach Web SSH:" "${WEBSSH_SERVER_IP:-$YOUR_SERVER_IP}")" || exit 0
[[ -n "$WEBSSH_SERVER_IP" ]] || WEBSSH_SERVER_IP="$YOUR_SERVER_IP"

WEBSSH_URL_FORMAT="$(ui_input "Step 3 of 4  •  Web SSH URL Template" \
  "URL template. Keep {SERVER_IP} and {PORT} placeholders:" "${WEBSSH_URL_FORMAT:-http://{SERVER_IP}:{PORT}}")" || exit 0
[[ -n "$WEBSSH_URL_FORMAT" ]] || WEBSSH_URL_FORMAT="http://{SERVER_IP}:{PORT}"

OWNER_IDS="$(ui_input "Step 3 of 4  •  Additional Owners" \
  "Comma-separated Discord User IDs allowed as bot owners.\nLeave blank to use only the main admin:" "${OWNER_IDS:-$MAIN_ADMIN_ID}")" || exit 0

while true; do
  if ui_yesno "Enable randomly generated PIN protection for new Web SSH links?"; then
    WEBSSH_DEFAULT_PIN="true"; break
  else
    WEBSSH_DEFAULT_PIN="false"; break
  fi
done

# Validate optional owner list.
if [[ -n "$OWNER_IDS" ]]; then
  IFS=',' read -ra owner_array <<< "$OWNER_IDS"
  valid_owners=true
  for owner_id in "${owner_array[@]}"; do
    owner_id="${owner_id//[[:space:]]/}"
    if ! valid_id "$owner_id"; then valid_owners=false; fi
  done
  if [[ "$valid_owners" != true ]]; then
    ui_msg "One or more extra owner IDs are invalid.\n\nUse comma-separated Discord IDs containing 15–25 digits."
    OWNER_IDS="$MAIN_ADMIN_ID"
  fi
fi

# ---------- Review ----------
summary="DISCORD BOT TOKEN       ••••••••••••••••\nMAIN ADMIN ID           $MAIN_ADMIN_ID\nVPS USER ROLE ID        ${VPS_USER_ROLE_ID:-Not set}\nVPS HOST                $YOUR_SERVER_IP\nCOMMAND PREFIX          $PREFIX\nLXD STORAGE POOL        $DEFAULT_STORAGE_POOL\nWEB SSH BIND            $WEBSSH_HOST:$WEBSSH_PORT\nWEB SSH PUBLIC HOST     $WEBSSH_SERVER_IP\nWEB SSH RANDOM PIN      $WEBSSH_DEFAULT_PIN\nEXTRA OWNER IDS         ${OWNER_IDS:-Main admin only}\n\nConfig will be saved to $APP_DIR/.env"
whiptail --title "Step 4 of 4  •  Review Configuration" \
  --backtitle "SANITY  •  FINAL REVIEW" --yesno "$summary\n\nStart installation with these settings?" 23 78 || exit 0

export DISCORD_TOKEN MAIN_ADMIN_ID VPS_USER_ROLE_ID YOUR_SERVER_IP PREFIX
export DEFAULT_STORAGE_POOL BOT_DEVELOPER WEBSSH_HOST WEBSSH_PORT WEBSSH_SERVER_IP
export WEBSSH_URL_FORMAT OWNER_IDS WEBSSH_DEFAULT_PIN

# ---------- Install ----------
(
  set -e
  echo 8
  apt-get install -y -qq python3 python3-venv python3-pip python3-dev \
    build-essential libffi-dev libssl-dev
  echo 22
  python3 - "$APP_DIR/.env" <<'PY'
import os, sys
from pathlib import Path

p = Path(sys.argv[1])
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
lines = p.read_text().splitlines() if p.exists() else []
out, seen = [], set()
for line in lines:
    if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
        out.append(line); continue
    key = line.split("=", 1)[0].strip()
    if key in updates:
        out.append(f"{key}={updates[key]}"); seen.add(key)
    else:
        out.append(line)
for k, v in updates.items():
    if k not in seen: out.append(f"{k}={v}")
p.write_text("\n".join(out) + "\n")
p.chmod(0o600)
PY
  echo 35
  python3 -m venv "$APP_DIR/venv"
  "$APP_DIR/venv/bin/python" -m pip install --quiet --upgrade pip wheel
  echo 55
  "$APP_DIR/venv/bin/pip" install --quiet discord.py python-dotenv PyNaCl \
    argon2-cffi cryptography paramiko Flask flask-cors psutil aiohttp requests
  echo 75
  "$APP_DIR/venv/bin/python" -m py_compile "$APP_DIR/bot.py"
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
  echo 90
  systemctl daemon-reload
  systemctl enable "$SERVICE.service" >/dev/null
  systemctl restart "$SERVICE.service"
  echo 100
) | whiptail --title "Installing Sanity" --backtitle "SANITY  •  PLEASE WAIT" \
    --gauge "Installing dependencies and configuring the service..." 9 72 0

unset DISCORD_TOKEN
sleep 2
if systemctl is-active --quiet "$SERVICE.service"; then
  status="ACTIVE"
else
  status="STARTING / CHECK LOGS"
fi

whiptail --title "SANITY INSTALLED" --backtitle "SANITY  •  COMPLETE" \
  --msgbox "Installation finished.\n\nService status: $status\n\nApplication: $APP_DIR\nConfiguration: $APP_DIR/.env\nWeb SSH page: $APP_DIR/webssh.html\n\nUseful commands:\nsystemctl status sanity\nsystemctl restart sanity\njournalctl -u sanity -f\n\nIMPORTANT: LXD/LXC must be installed and initialized separately. Secure the Web SSH port with your firewall or reverse proxy." 22 76

clear
echo "Sanity installation finished. Check: systemctl status sanity"
