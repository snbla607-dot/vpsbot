#!/usr/bin/env bash
# SANITY VPS BOT INSTALLER
# Repository: https://github.com/snbla607-dot/vpsbot

set -Eeuo pipefail

APP_NAME="Sanity"
REPO_URL="https://github.com/snbla607-dot/vpsbot.git"
INSTALL_DIR="/opt/sanity"
SERVICE_NAME="sanity"

# ─────────────── COLORS ───────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─────────────── BRANDING ───────────────
watermark() {
    echo -e "${MAGENTA}${DIM}             ────────── SANITY ──────────${NC}"
}

typewriter() {
    local text="$1" delay="${2:-0.012}"
    for ((i=0; i<${#text}; i++)); do
        printf '%s' "${text:$i:1}"
        sleep "$delay"
    done
    echo
}

spinner() {
    local pid="$1" message="$2"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}  ${spin:$i:1} ${WHITE}%s${NC}   " "$message"
        i=$(( (i + 1) % 10 ))
        sleep 0.12
    done
    wait "$pid"
    local rc=$?
    if (( rc == 0 )); then
        printf "\r${GREEN}  ✔ ${WHITE}%s ${GREEN}[DONE]${NC}                 \n" "$message"
    else
        printf "\r${RED}  ✖ %s [FAILED]${NC}                 \n" "$message"
        return "$rc"
    fi
}

section() {
    echo
    echo -e "${CYAN}  ┌──────────────────────────────────────────────────────┐${NC}"
    printf "${CYAN}  │${NC} ${BLUE}${BOLD}[STEP %-3s]${NC} ${WHITE}${BOLD}%-43s${NC}${CYAN}│${NC}\n" "$1" "$2"
    echo -e "${CYAN}  └──────────────────────────────────────────────────────┘${NC}"
    watermark
    echo
}

line() {
    echo -e "${CYAN}  ════════════════════════════════════════════════════════${NC}"
}

fail() {
    echo -e "\n${RED}${BOLD}  ✖ $*${NC}" >&2
    echo -e "${YELLOW}  Check the error above, then run the installer again.${NC}" >&2
    exit 1
}

# Keep installer output readable in SSH sessions.
clear 2>/dev/null || true
echo
echo -e "${CYAN}${BOLD}"
cat <<'EOF'
      ╔═══════════════════════════════════════════════════════╗
      ║                                                       ║
      ║                    S A N I T Y                        ║
      ║               VPS BOT INSTALLER                       ║
      ║                                                       ║
      ╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo -e "${YELLOW}${BOLD}"
typewriter "             SANITY VPS BOT — AUTO SETUP WIZARD" 0.015
echo -e "${NC}"
watermark
echo

# ─────────────── ROOT CHECK ───────────────
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}  ✖ Please run this installer as root.${NC}"
    echo -e "${YELLOW}  → sudo bash install.sh${NC}"
    exit 1
fi
echo -e "${GREEN}  ✔ Root access confirmed${NC}"
watermark

# ─────────────── INTERACTIVE INPUT HELPERS ───────────────
prompt_value() {
    local var_name="$1" prompt_text="$2" default_value="${3:-}" value=""
    echo -e "${YELLOW}  ➤ ${BOLD}${var_name}${NC}"
    echo -e "${DIM}    ${prompt_text}${NC}"
    if [[ -n "$default_value" ]]; then
        read -r -p "    ${var_name} [${default_value}]: " value
        value="${value:-$default_value}"
    else
        read -r -p "    ${var_name}: " value
    fi
    printf -v "$var_name" '%s' "$value"
    echo
}

prompt_secret() {
    local var_name="$1" prompt_text="$2" value=""
    echo -e "${YELLOW}  ➤ ${BOLD}${var_name}${NC}"
    echo -e "${DIM}    ${prompt_text}${NC}"
    while true; do
        read -r -s -p "    ${var_name}: " value
        echo
        if [[ -n "$value" ]]; then
            printf -v "$var_name" '%s' "$value"
            break
        fi
        echo -e "${RED}    ✖ This value is required.${NC}"
    done
    echo
}

valid_discord_id() {
    [[ "$1" =~ ^[0-9]{15,25}$ ]]
}

# ─────────────── STEP 1: DEPENDENCIES ───────────────
section "1/7" "Installing System Dependencies"

export DEBIAN_FRONTEND=noninteractive
(apt-get update -y >/dev/null 2>&1) &
spinner "$!" "Updating package lists"

(apt-get install -y git python3 python3-venv python3-pip python3-dev \
    build-essential libffi-dev libssl-dev curl wget nano ca-certificates \
    >/dev/null 2>&1) &
spinner "$!" "Installing Git, Python and system packages"

echo -e "${GREEN}  ✔ System dependencies installed${NC}"
watermark

# ─────────────── STEP 2: REPOSITORY ───────────────
section "2/7" "Downloading Sanity Repository"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo -e "${YELLOW}  ⚠ Existing Sanity installation found. Updating files...${NC}"
    (git -C "$INSTALL_DIR" fetch --depth 1 origin main >/dev/null 2>&1 &&
     git -C "$INSTALL_DIR" reset --hard origin/main >/dev/null 2>&1) &
    spinner "$!" "Updating Sanity from GitHub"
else
    if [[ -e "$INSTALL_DIR" ]]; then
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    fi
    (git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1) &
    spinner "$!" "Cloning Sanity repository"
fi

[[ -f "$INSTALL_DIR/bot.py" ]] || fail "bot.py was not found in the repository."
[[ -f "$INSTALL_DIR/webssh.html" ]] || fail "webssh.html was not found in the repository."

cd "$INSTALL_DIR"
# The upstream repository currently includes an env file; do not keep its credentials.
rm -f "$INSTALL_DIR/env"
echo -e "${GREEN}  ✔ Repository downloaded${NC}"
echo -e "${CYAN}  ℹ Install directory: ${WHITE}${INSTALL_DIR}${NC}"
watermark

# ─────────────── STEP 3: PYTHON ENVIRONMENT ───────────────
section "3/7" "Preparing Python Environment"

python3 -m venv "$INSTALL_DIR/venv"
("$INSTALL_DIR/venv/bin/python" -m pip install --upgrade pip wheel >/dev/null 2>&1) &
spinner "$!" "Preparing isolated Python environment"

("$INSTALL_DIR/venv/bin/pip" install --quiet \
    discord.py python-dotenv PyNaCl argon2-cffi cryptography \
    paramiko Flask flask-cors psutil aiohttp requests >/dev/null 2>&1) &
spinner "$!" "Installing Sanity Python packages"

echo -e "${GREEN}  ✔ Python environment ready${NC}"
watermark

# ─────────────── STEP 4: CONFIGURATION WIZARD ───────────────
section "4/7" "Configuring Sanity Environment"

echo -e "${CYAN}  ┌────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}  │${NC}  ${WHITE}${BOLD}SANITY CONFIGURATION WIZARD${NC}                         ${CYAN}│${NC}"
echo -e "${CYAN}  │${NC}  ${DIM}Enter your settings. Press ENTER to use defaults.${NC}   ${CYAN}│${NC}"
echo -e "${CYAN}  └────────────────────────────────────────────────────────┘${NC}"
watermark
echo

# Discord
echo -e "${MAGENTA}${BOLD}  ╭─── DISCORD CONFIGURATION ───╮${NC}"
watermark
prompt_secret "DISCORD_TOKEN" "Discord bot token (input is hidden)"
BOT_NAME="Sanity"
prompt_value "PREFIX" "Bot command prefix" "!"
AUTO_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
AUTO_IP="${AUTO_IP:-127.0.0.1}"
prompt_value "MAIN_ADMIN_ID" "Your Discord user ID (required)" ""
while ! valid_discord_id "$MAIN_ADMIN_ID"; do
    echo -e "${RED}  ✖ Enter a valid Discord ID (15–25 digits).${NC}"
    prompt_value "MAIN_ADMIN_ID" "Your Discord user ID" ""
done
prompt_value "VPS_USER_ROLE_ID" "VPS user role ID (optional; leave blank if unused)" ""
if [[ -n "$VPS_USER_ROLE_ID" ]] && ! valid_discord_id "$VPS_USER_ROLE_ID"; then
    echo -e "${YELLOW}  ⚠ Invalid role ID; leaving it empty.${NC}"
    VPS_USER_ROLE_ID=""
fi

# Server info
echo -e "${MAGENTA}${BOLD}  ╭─── SERVER CONFIGURATION ───╮${NC}"
watermark
prompt_value "YOUR_SERVER_IP" "Public VPS IP address (auto-detected)" "$AUTO_IP"
prompt_value "DEFAULT_STORAGE_POOL" "Existing LXD storage pool name" "default"

# Metadata
echo -e "${MAGENTA}${BOLD}  ╭─── BOT INFORMATION ───╮${NC}"
watermark
prompt_value "BOT_VERSION" "Version label" "Sanity"
prompt_value "BOT_DEVELOPER" "Developer/team label" "Sanity"
prompt_value "BOT_THUMBNAIL_URL" "Embed thumbnail URL (optional)" ""
prompt_value "BOT_ICON_URL" "Embed icon URL (optional)" ""

# Expiration
echo -e "${MAGENTA}${BOLD}  ╭─── VPS EXPIRATION ───╮${NC}"
watermark
prompt_value "DEFAULT_VPS_EXPIRATION_DAYS" "Default VPS expiry in days" "30"
prompt_value "EXPIRATION_WARNING_DAYS" "Days before expiry warning" "3"
prompt_value "EXPIRATION_AUTO_SUSPEND" "Automatically suspend expired VPS (true/false)" "true"
prompt_value "EXPIRATION_CHECK_INTERVAL" "Expiry check interval in seconds" "900"

# Public VPS
echo -e "${MAGENTA}${BOLD}  ╭─── PUBLIC VPS LIMITS ───╮${NC}"
watermark
prompt_value "PUBLIC_VPS_ENABLED" "Enable public VPS creation (true/false)" "true"
prompt_value "PUBLIC_VPS_MAX_RAM" "Maximum RAM per VPS (GB)" "8"
prompt_value "PUBLIC_VPS_MAX_CPU" "Maximum CPU cores per VPS" "2"
prompt_value "PUBLIC_VPS_MAX_DISK" "Maximum disk per VPS (GB)" "40"
prompt_value "PUBLIC_VPS_EXPIRY_DAYS" "Public VPS expiry days" "3"
prompt_value "PUBLIC_VPS_MAX_PER_USER" "Maximum VPS per user" "1"
prompt_value "PUBLIC_VPS_MAX_PER_IP" "Maximum VPS per IP" "1"
prompt_value "PUBLIC_VPS_GLOBAL_LIMIT" "Global public VPS limit" "100"
prompt_value "PUBLIC_VPS_REQUIRE_VERIFICATION" "Require user verification (true/false)" "false"
prompt_value "PUBLIC_VPS_REQUIRE_ACCOUNT_AGE" "Minimum account age (days)" "3"

# Renewal
echo -e "${MAGENTA}${BOLD}  ╭─── VPS RENEWAL ───╮${NC}"
watermark
prompt_value "PUBLIC_VPS_RENEWAL_ENABLED" "Enable VPS renewal (true/false)" "true"
prompt_value "PUBLIC_VPS_RENEWAL_DAYS" "Renewal duration in days" "3"
prompt_value "PUBLIC_VPS_RENEWAL_WINDOW_DAYS" "Renewal window before expiry (days)" "1"
prompt_value "PUBLIC_VPS_COOLDOWN_HOURS" "Renewal cooldown in hours" "24"

# Rate limits
echo -e "${MAGENTA}${BOLD}  ╭─── RATE LIMITING ───╮${NC}"
watermark
prompt_value "RATE_LIMIT_COOLDOWN" "Rate-limit cooldown" "2"
prompt_value "RATE_LIMIT_BURST" "Maximum burst requests" "5"
prompt_value "RATE_LIMIT_MAX_VIOLATIONS" "Maximum violations" "5"
prompt_value "RATE_LIMIT_ABUSE_TIMEOUT" "Abuse timeout in seconds" "120"

# Host MOTD
echo -e "${MAGENTA}${BOLD}  ╭─── HOST MESSAGE ───╮${NC}"
watermark
prompt_value "HOST_MOTD" "Optional MOTD script URL/command (leave blank to disable)" ""

# Web SSH
echo -e "${MAGENTA}${BOLD}  ╭─── WEB SSH TERMINAL ───╮${NC}"
watermark
prompt_value "WEBSSH_HOST" "Web SSH bind address" "0.0.0.0"
prompt_value "WEBSSH_PORT" "Web SSH port" "5000"
prompt_value "WEBSSH_SERVER_IP" "Public Web SSH hostname/IP" "$AUTO_IP"
prompt_value "WEBSSH_URL_FORMAT" "URL format" "http://{SERVER_IP}:{PORT}"
prompt_value "WEBSSH_SESSION_TTL" "Session lifetime in seconds" "1800"
prompt_value "WEBSSH_MAX_SESSIONS" "Maximum concurrent sessions" "200"
prompt_value "WEBSSH_SESSION_MAX_PER_IP" "Maximum sessions per IP" "8"
prompt_value "WEBSSH_ALLOW_PRIVATE_HOSTS" "Allow private hosts (true/false)" "true"
prompt_value "WEBSSH_DEFAULT_PIN" "Enable random PIN by default (true/false)" "false"
prompt_value "WEBSSH_PIN_ATTEMPTS" "Maximum PIN attempts" "5"
prompt_value "WEBSSH_CONNECT_TIMEOUT" "Connection timeout in seconds" "15"

# Timeouts and stats
echo -e "${MAGENTA}${BOLD}  ╭─── SYSTEM SETTINGS ───╮${NC}"
watermark
prompt_value "LXC_TIMEOUT_DEFAULT" "Default LXC operation timeout" "180"
prompt_value "COMMAND_TIMEOUT_SECONDS" "Command timeout in seconds" "240"
prompt_value "MANAGE_PANEL_TIMEOUT" "Manage panel timeout" "300"
prompt_value "CONSOLE_PANEL_TIMEOUT" "Console panel timeout" "600"
prompt_value "STATS_REFRESH_SECONDS" "Stats refresh interval" "5"
prompt_value "MAX_LIVE_REFRESHES" "Maximum live refreshes" "60"
prompt_value "OWNER_IDS" "Extra owner Discord IDs (comma-separated; optional)" "$MAIN_ADMIN_ID"

# ─────────────── WRITE ENV SAFELY ───────────────
# Use Python to quote/escape values safely and never echo secrets.
export BOT_NAME PREFIX DISCORD_TOKEN YOUR_SERVER_IP MAIN_ADMIN_ID VPS_USER_ROLE_ID
export DEFAULT_STORAGE_POOL BOT_VERSION BOT_DEVELOPER BOT_THUMBNAIL_URL BOT_ICON_URL
export DEFAULT_VPS_EXPIRATION_DAYS EXPIRATION_WARNING_DAYS EXPIRATION_AUTO_SUSPEND EXPIRATION_CHECK_INTERVAL
export PUBLIC_VPS_ENABLED PUBLIC_VPS_MAX_RAM PUBLIC_VPS_MAX_CPU PUBLIC_VPS_MAX_DISK PUBLIC_VPS_EXPIRY_DAYS
export PUBLIC_VPS_MAX_PER_USER PUBLIC_VPS_MAX_PER_IP PUBLIC_VPS_GLOBAL_LIMIT PUBLIC_VPS_REQUIRE_VERIFICATION
export PUBLIC_VPS_REQUIRE_ACCOUNT_AGE PUBLIC_VPS_RENEWAL_ENABLED PUBLIC_VPS_RENEWAL_DAYS
export PUBLIC_VPS_RENEWAL_WINDOW_DAYS PUBLIC_VPS_COOLDOWN_HOURS RATE_LIMIT_COOLDOWN RATE_LIMIT_BURST
export RATE_LIMIT_MAX_VIOLATIONS RATE_LIMIT_ABUSE_TIMEOUT HOST_MOTD WEBSSH_HOST WEBSSH_PORT
export WEBSSH_SERVER_IP WEBSSH_URL_FORMAT WEBSSH_SESSION_TTL WEBSSH_MAX_SESSIONS WEBSSH_SESSION_MAX_PER_IP
export WEBSSH_ALLOW_PRIVATE_HOSTS WEBSSH_DEFAULT_PIN WEBSSH_PIN_ATTEMPTS WEBSSH_CONNECT_TIMEOUT
export LXC_TIMEOUT_DEFAULT COMMAND_TIMEOUT_SECONDS MANAGE_PANEL_TIMEOUT CONSOLE_PANEL_TIMEOUT
export STATS_REFRESH_SECONDS MAX_LIVE_REFRESHES OWNER_IDS

python3 - "$INSTALL_DIR/.env" <<'PY'
import os, sys
from pathlib import Path

keys = """
DISCORD_TOKEN BOT_NAME PREFIX YOUR_SERVER_IP MAIN_ADMIN_ID VPS_USER_ROLE_ID
DEFAULT_STORAGE_POOL BOT_VERSION BOT_DEVELOPER BOT_THUMBNAIL_URL BOT_ICON_URL
DEFAULT_VPS_EXPIRATION_DAYS EXPIRATION_WARNING_DAYS EXPIRATION_AUTO_SUSPEND EXPIRATION_CHECK_INTERVAL
PUBLIC_VPS_ENABLED PUBLIC_VPS_MAX_RAM PUBLIC_VPS_MAX_CPU PUBLIC_VPS_MAX_DISK PUBLIC_VPS_EXPIRY_DAYS
PUBLIC_VPS_MAX_PER_USER PUBLIC_VPS_MAX_PER_IP PUBLIC_VPS_GLOBAL_LIMIT PUBLIC_VPS_REQUIRE_VERIFICATION
PUBLIC_VPS_REQUIRE_ACCOUNT_AGE PUBLIC_VPS_RENEWAL_ENABLED PUBLIC_VPS_RENEWAL_DAYS
PUBLIC_VPS_RENEWAL_WINDOW_DAYS PUBLIC_VPS_COOLDOWN_HOURS RATE_LIMIT_COOLDOWN RATE_LIMIT_BURST
RATE_LIMIT_MAX_VIOLATIONS RATE_LIMIT_ABUSE_TIMEOUT HOST_MOTD WEBSSH_HOST WEBSSH_PORT
WEBSSH_SERVER_IP WEBSSH_URL_FORMAT WEBSSH_SESSION_TTL WEBSSH_MAX_SESSIONS WEBSSH_SESSION_MAX_PER_IP
WEBSSH_ALLOW_PRIVATE_HOSTS WEBSSH_DEFAULT_PIN WEBSSH_PIN_ATTEMPTS WEBSSH_CONNECT_TIMEOUT
LXC_TIMEOUT_DEFAULT COMMAND_TIMEOUT_SECONDS MANAGE_PANEL_TIMEOUT CONSOLE_PANEL_TIMEOUT
STATS_REFRESH_SECONDS MAX_LIVE_REFRESHES OWNER_IDS
""".split()

# Keep any unrecognized upstream settings, but replace all known values.
path = Path(sys.argv[1])
lines = path.read_text().splitlines() if path.exists() else []
known = set(keys)
out, seen = [], set()
for line in lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in line:
        out.append(line)
        continue
    key = line.split("=", 1)[0].strip()
    if key in known:
        continue
    # Never retain a repository-provided credential.
    if key in {"TOKEN", "DISCORD_TOKEN", "BOT_TOKEN", "PASSWORD", "SECRET"}:
        continue
    out.append(line)

for key in keys:
    value = os.environ.get(key, "")
    out.append(f"{key}={value}")

path.write_text("\n".join(out) + "\n")
path.chmod(0o600)
PY
unset DISCORD_TOKEN

echo
echo -e "${GREEN}${BOLD}  ✔ Sanity .env configuration saved${NC}"
echo -e "${CYAN}  ℹ Secrets are hidden and .env permissions are set to 600.${NC}"
watermark
echo

# ─────────────── STEP 5: CHECK APPLICATION ───────────────
section "5/7" "Checking Sanity Application"

"$INSTALL_DIR/venv/bin/python" -m py_compile "$INSTALL_DIR/bot.py" \
    || fail "Python syntax check failed. See the error above."

echo -e "${GREEN}  ✔ bot.py syntax check passed${NC}"
echo -e "${GREEN}  ✔ webssh.html found${NC}"
watermark

# ─────────────── STEP 6: CREATE SERVICE ───────────────
section "6/7" "Creating Sanity System Service"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Sanity VPS Management Bot
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
Environment=PYTHONUNBUFFERED=1
ExecStart=${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/bot.py
Restart=always
RestartSec=5
UMask=0077

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}  ✔ ${SERVICE_NAME}.service created${NC}"
watermark

# ─────────────── STEP 7: ENABLE & START ───────────────
section "7/7" "Starting Sanity Service"

(systemctl daemon-reload >/dev/null 2>&1) &
spinner "$!" "Reloading systemd"

(systemctl enable "$SERVICE_NAME" >/dev/null 2>&1) &
spinner "$!" "Enabling Sanity auto-start"

(systemctl restart "$SERVICE_NAME" >/dev/null 2>&1) &
spinner "$!" "Starting Sanity bot"

sleep 3
if systemctl is-active --quiet "$SERVICE_NAME"; then
    STATUS="${GREEN}${BOLD}RUNNING${NC}"
    echo -e "${GREEN}${BOLD}  ✔ Sanity service is RUNNING${NC}"
else
    STATUS="${RED}${BOLD}FAILED${NC}"
    echo -e "${RED}${BOLD}  ✖ Sanity service did not start successfully${NC}"
    echo -e "${YELLOW}  → Check: journalctl -u sanity -n 100 --no-pager${NC}"
fi

if ! command -v lxc >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ LXC/LXD is not installed. Container features need LXD/LXC configured separately.${NC}"
fi

# ─────────────── FINAL SCREEN ───────────────
echo
echo -e "${GREEN}${BOLD}"
cat <<'EOF'
      ╔═══════════════════════════════════════════════════════╗
      ║                                                       ║
      ║               INSTALLATION COMPLETE                   ║
      ║                                                       ║
      ║                    S A N I T Y                        ║
      ║                                                       ║
      ╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
watermark
echo
echo -e "${CYAN}  📊 ${BOLD}STATUS:${NC}       ${STATUS}"
echo -e "${CYAN}  📁 ${BOLD}DIRECTORY:${NC}    ${WHITE}${INSTALL_DIR}${NC}"
echo -e "${CYAN}  📄 ${BOLD}CONFIG:${NC}       ${WHITE}${INSTALL_DIR}/.env${NC}"
echo -e "${CYAN}  🌐 ${BOLD}WEB SSH:${NC}      ${WHITE}${INSTALL_DIR}/webssh.html${NC}"
echo -e "${CYAN}  ⚙️  ${BOLD}SERVICE:${NC}      ${WHITE}${SERVICE_NAME}.service${NC}"
echo
watermark
echo
echo -e "${YELLOW}${BOLD}  USEFUL COMMANDS${NC}"
watermark
echo -e "     ${CYAN}systemctl status sanity${NC}       ${DIM}→ Check status${NC}"
echo -e "     ${CYAN}systemctl restart sanity${NC}      ${DIM}→ Restart bot${NC}"
echo -e "     ${CYAN}systemctl stop sanity${NC}         ${DIM}→ Stop bot${NC}"
echo -e "     ${CYAN}journalctl -u sanity -f${NC}       ${DIM}→ Live logs${NC}"
echo -e "     ${CYAN}nano /opt/sanity/.env${NC}         ${DIM}→ Edit configuration${NC}"
echo
watermark
echo
echo -e "${MAGENTA}${BOLD}                 Thanks for using Sanity.${NC}"
watermark
echo
