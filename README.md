# Sanity — Discord VPS Management Bot

Sanity is a Discord-based VPS/LXC management bot with a companion Web SSH interface. It is designed for an administrator-managed Linux host.

## Features

### VPS lifecycle and resources
- Create and list VPS/LXC containers
- Restart, suspend, unsuspend, renew, and delete VPS instances
- Set expiration dates and automatic expiration handling
- Resize CPU, RAM, and disk resources
- View VPS information, live statistics, processes, network details, uptime, and logs
- Assign existing containers and migrate VPS instances

### Users, access, and administration
- VPS ownership, sharing, and ownership transfer
- Admin add/remove/list commands
- Whitelist and permission management
- VPS suspension records and audit logs
- Port allocation and port management
- Broadcast and maintenance-style administrative controls

### Monitoring and dashboards
- Host uptime and system status
- Live dashboard, charts, and resource views
- Server/node and resource checks
- Threshold configuration and status/presence controls

### Web SSH
- Companion `webssh.html` browser terminal interface
- Configurable Web SSH host, port, session lifetime, and session limits

### Safety and operations
- Configurable command timeouts and rate limits
- VPS/container audit and hardening-related commands
- Database backup and audit-log commands

> Feature availability depends on the host setup and the values configured in `.env`. LXD/LXC must be installed and initialized separately. Review command permissions and Web SSH exposure before putting the bot online.

## One-line installation

On a supported Ubuntu/Debian VPS, run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/snbla607-dot/vpsbot/main/install.sh)
```

The installer downloads `bot.py`, `webssh.html`, and `.env.example` from this repository, creates `/opt/sanity`, creates a Python virtual environment, and installs the `sanity` systemd service. On first run it creates `/opt/sanity/.env` and stops so you can add your credentials.

Then configure and start it:

```bash
nano /opt/sanity/.env
systemctl restart sanity
systemctl status sanity
journalctl -u sanity -f
```

## Configuration

Copy `.env.example` to `.env` (the installer does this automatically). Set at least:

- `DISCORD_TOKEN` — your Discord bot token
- `MAIN_ADMIN_ID` — your Discord user ID
- `YOUR_SERVER_IP` — the host address used by your setup
- `VPS_USER_ROLE_ID` — the Discord role ID allowed to use VPS features
- Web SSH settings — configure host, port, URL format, and session limits to match your network

Never commit `.env` or real tokens, IDs, passwords, or private PINs to a public repository. Keep `.env` private and mode `600`. If a token was ever committed publicly, revoke it and create a replacement.

## Requirements

- Ubuntu/Debian Linux VPS with root access
- Discord bot application and token
- LXD/LXC installed and initialized for container provisioning
- Network/firewall rules configured for the Web SSH port if you intend to expose it

## Repository files

- `bot.py` — Discord bot
- `webssh.html` — Web SSH frontend
- `.env.example` — safe configuration template
- `install.sh` — one-line installer
- `README.md` — documentation

## Service management

```bash
systemctl status sanity
systemctl restart sanity
systemctl stop sanity
journalctl -u sanity -f
```
