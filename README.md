# Sanity — Discord VPS Management Bot

Sanity is a Discord-based VPS/LXC management bot with a companion Web SSH interface.

## Features

### VPS lifecycle and resources
- Create, list, restart, suspend, unsuspend, renew, and delete VPS/LXC containers
- Configure CPU, RAM, and disk resources
- Expiration dates, automatic suspension, and renewal handling
- VPS information, live statistics, processes, network details, uptime, and logs
- Assign existing containers and migrate VPS instances

### Users, access, and administration
- VPS ownership, sharing, and ownership transfer
- Admin add/remove/list commands
- Whitelist and permission management
- VPS suspension records and audit logs
- Port allocation and port management
- Broadcast and maintenance-style administrative controls

### Monitoring and Web SSH
- Host uptime, system status, dashboards, charts, and resource views
- Browser-based Web SSH terminal
- Configurable Web SSH port, session lifetime, session limits, and random PIN protection

### Safety and operations
- Configurable command timeouts and rate limits
- Container audit and database backup commands
- Role-based VPS access controls

> Feature availability depends on host setup and `.env` settings. LXD/LXC must be installed and initialized separately. Review firewall rules and Web SSH exposure before production use.

## One-line installation

On Ubuntu/Debian, run as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/snbla607-dot/vpsbot/main/install.sh)
```

The installer downloads the application and starts an interactive setup wizard. You enter the Discord token, main admin ID, optional VPS role ID, VPS public IP/hostname, command prefix, storage pool, Web SSH settings, and extra owner IDs during installation. The token is hidden while typing.

The wizard writes the values to `/opt/sanity/.env` with file permissions `600`, installs Python dependencies, and creates/enables the `sanity` systemd service.

## What you need before installing

1. A Discord application and bot token from the Discord Developer Portal.
2. Your Discord user ID for the main admin.
3. Your VPS public IP or public hostname.
4. An initialized LXD/LXC host for container provisioning.

To copy Discord IDs, enable Developer Mode in Discord and use Copy ID. You can leave the VPS role ID blank if you want Sanity to manage/create its role.

## Service management

```bash
systemctl status sanity
systemctl restart sanity
systemctl stop sanity
journalctl -u sanity -f
```

Configuration is stored at `/opt/sanity/.env`. To change settings later:

```bash
nano /opt/sanity/.env
systemctl restart sanity
```

## Repository files

- `bot.py` — Discord bot application
- `webssh.html` — Web SSH frontend
- `.env.example` — safe configuration template; no live secrets
- `install.sh` — interactive one-line installer
- `README.md` — documentation

## Security

- Never commit `.env`, real Discord tokens, private keys, or passwords to a public repository.
- If a token was ever exposed publicly, revoke it in the Discord Developer Portal and generate a replacement.
- Keep `/opt/sanity/.env` private (`600`).
- Keep Web SSH behind appropriate firewall rules or a trusted reverse proxy.
