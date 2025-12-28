[![ru](https://img.shields.io/badge/lang-ru-green.svg)](README.md)
[![en](https://img.shields.io/badge/lang-en-red.svg)](README_EN.md)

# Install Scripts

A collection of scripts for automatic installation of various software on remote Ubuntu 24.04 servers.

If the software you need is not available in the list of scripts, you can [create an issue](https://github.com/andchir/install_scripts/issues/new) with a request to add an installation script for it.

## Project Description

This project provides a set of bash scripts for quick deployment of popular software on Ubuntu servers. All scripts:

- Are adapted for Ubuntu 24.04
- Support idempotency (can be run multiple times)
- Automatically create necessary users
- Configure nginx with SSL certificates (Let's Encrypt)
- Display installation results with color highlighting

![screenshot](https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/screenshots/gui_en.png)

## Available Scripts

| Script | Description | Installed Components |
|--------|-------------|---------------------|
| `install-scripts-api-flask.sh` | API for installing software on a remote Ubuntu server | Git, Python 3, pip, venv, Nginx, Certbot, Flask, Gunicorn, systemd service |
| `various-useful-api-django.sh` | A collection of useful APIs using Django | Git, Python 3, pip, venv, MySQL, Nginx, Certbot, Django, Gunicorn, FFmpeg, systemd service |
| `openchatroulette.sh` | Video chat roulette with WebRTC | Git, Node.js, npm, Nginx, Certbot, Angular, GeoLite2-Country database, systemd service |
| `pocketbase.sh` | Go backend with built-in SQLite database, authentication and admin dashboard | Nginx, Certbot, PocketBase, systemd service |
| `mysql-phpmyadmin.sh` | MySQL database server with phpMyAdmin web interface | Nginx, PHP-FPM with extensions, MySQL Server, phpMyAdmin, Certbot |
| `postgresql-mathesar.sh` | PostgreSQL database server with Mathesar web interface | Nginx, Certbot, PostgreSQL 16, Mathesar, systemd service |
| `filebrowser.sh` | Web file manager with modern interface | Nginx, Certbot, FileBrowser Quantum, systemd service |
| `wireguard-wireguard-ui.sh` | WireGuard VPN server with web management interface | WireGuard, WireGuard-UI, Nginx, Certbot, IP forwarding configuration, systemd services |
| `xray-3x-ui.sh` | Xray proxy server with 3x-ui web panel (VLESS, VMess, Trojan) | Xray, 3x-ui panel, Nginx, Certbot, systemd services |
| `wordpress.sh` | WordPress CMS with MySQL, Nginx and SSL certificate | WordPress, MySQL Server, Nginx, PHP-FPM with extensions, Certbot, WP-CLI |
| `n8n.sh` | n8n workflow automation platform | Docker, Docker Compose, PostgreSQL 16, n8n, Nginx, Certbot |
| `rocketchat.sh` | Rocket.Chat messaging platform | Docker, Docker Compose, MongoDB 6.0 with replica set, Rocket.Chat, Nginx, Certbot |
| `jitsi-meet.sh` | Jitsi Meet video conferencing platform | Prosody XMPP, Jitsi Videobridge, Jicofo, Nginx, Certbot |
| `netdata.sh` | Real-time server monitoring system | Netdata, Nginx, Certbot, basic authentication |
| `uptime-kuma.sh` | Self-hosted uptime monitoring tool | Git, Node.js 20.x, npm, Nginx, Certbot, systemd service |
| `linux-dash.sh` | Linux server monitoring dashboard | Git, Python 3, linux-dash, Nginx, Certbot, basic authentication, systemd service |
| `teable.sh` | Spreadsheet-database platform Teable | Docker, Docker Compose, PostgreSQL 15, Redis 7, Teable, Nginx, Certbot |
| `hive-mind.sh` | Hive Mind AI orchestrator with Telegram bot | Docker, Docker Compose, Hive Mind, Telegram Bot, Nginx, Certbot |

## Usage

### Running a Script Directly

```bash
curl -fsSL -o- https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts/<script_name>.sh | bash -s -- <domain_name>
```

Example:
```bash
curl -fsSL -o- https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts/pocketbase.sh | bash -s -- example.com
```

### Using via API

The project includes a Flask API for managing scripts and remote software installation.

## API

### Starting the API Server

```bash
cd api
pip install flask paramiko
python app.py --port 5000 --host 0.0.0.0
```

### Environment Variables

You can set environment variables in a `.env` file in the `api/` directory. Example file: `api/.env.example`.

| Variable | Description | Default |
|----------|-------------|---------|
| `API_KEY` | API key for authentication (if not set, authentication is disabled) | - |
| `SCRIPTS_DIR` | Directory with scripts | `../scripts` |
| `DATA_DIR` | Directory with data files | `..` |
| `SCRIPTS_BASE_URL` | Base URL for downloading scripts | `https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts` |

### API Authentication

If the `API_KEY` environment variable is set, the `/api/install` endpoint requires an API key for access.

The API key can be provided via:
- Header: `X-API-Key`
- Query parameter: `api_key`

**Generating a secure key:**
```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

### API Endpoints

#### `GET /`

API information and list of available endpoints.

**Response:**
```json
{
  "name": "Install Scripts API",
  "version": "1.0.0",
  "endpoints": {
    "/": "API information (this page)",
    "/health": "Health check endpoint",
    "/api/scripts_list": "List all available installation scripts (supports ?lang=ru|en)",
    "/api/script/<script_name>": "Get information about a single script by script_name (supports ?lang=ru|en)",
    "/api/install": "Execute an installation script on a remote server via SSH (POST: script_name, server_ip, server_root_password, additional)"
  }
}
```

#### `GET /health`

Health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "message": "API is running"
}
```

#### `GET /api/scripts_list`

Get a list of all available scripts.

**Query Parameters:**
| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `lang` | string | Data language (`ru` or `en`) | `ru` |

**Example Request:**
```bash
curl http://localhost:5000/api/scripts_list?lang=en
```

**Response:**
```json
{
  "success": true,
  "count": 4,
  "scripts": [
    {
      "name": "andchir/install_scripts",
      "script_name": "install-scripts-api-flask",
      "description": "API for installing software on a remote Ubuntu server",
      "info": "Required parameter: domain name"
    }
  ]
}
```

#### `GET /api/script/<script_name>`

Get information about a specific script.

**URL Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `script_name` | string | Script name (without `.sh` extension) |

**Query Parameters:**
| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `lang` | string | Data language (`ru` or `en`) | `ru` |

**Example Request:**
```bash
curl http://localhost:5000/api/script/pocketbase?lang=en
```

**Response:**
```json
{
  "success": true,
  "result": {
    "name": "pocketbase/pocketbase",
    "script_name": "pocketbase",
    "description": "Go backend with built-in SQLite database, authentication, file storage and admin dashboard",
    "info": "Required parameter: domain name"
  }
}
```

#### `POST /api/install`

Execute software installation on a remote server via SSH.

**Requires API key authentication** if the `API_KEY` variable is set.

**Headers:**
```
Content-Type: application/json
X-API-Key: your_api_key (if API_KEY is set)
```

**Request Body:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `script_name` | string | Yes | Name of the script to execute |
| `server_ip` | string | Yes | IP address of the remote server |
| `server_root_password` | string | Yes | Root password for SSH |
| `additional` | string | No | Additional parameters for the script (e.g., domain name) |

**Example Request (with API key):**
```bash
curl -X POST http://localhost:5000/api/install \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your_api_key" \
  -d '{
    "script_name": "pocketbase",
    "server_ip": "192.168.1.100",
    "server_root_password": "your_password",
    "additional": "example.com"
  }'
```

**Success Response:**
```json
{
  "success": true,
  "output": "...",
  "error": null
}
```

**Error Response:**
```json
{
  "success": false,
  "output": "...",
  "error": "SSH authentication failed. Please check the password."
}
```

### Response Codes

| Code | Description |
|------|-------------|
| 200 | Successful request |
| 400 | Bad request (missing required fields) |
| 401 | Authentication required (missing or invalid API key) |
| 403 | Access denied |
| 404 | Resource not found |
| 500 | Internal server error |
| 503 | Service unavailable (paramiko library not installed) |

## Script Requirements

Detailed requirements for scripts are described in [requirements_for_scripts_ru.md](requirements_for_scripts_ru.md) (in Russian).

## License

MIT
