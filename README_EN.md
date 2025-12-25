# Install Scripts

A collection of scripts for automatic installation of various software on remote Ubuntu 24.04 servers.

## Project Description

This project provides a set of bash scripts for quick deployment of popular software on Ubuntu servers. All scripts:

- Are adapted for Ubuntu 24.04
- Support idempotency (can be run multiple times)
- Automatically create necessary users
- Configure nginx with SSL certificates (Let's Encrypt)
- Display installation results with color highlighting

## Available Scripts

| Script | Description |
|--------|-------------|
| `install-scripts-api-flask.sh` | API for installing software on a remote Ubuntu server |
| `various-useful-api-django.sh` | A collection of useful APIs using Django |
| `openchatroulette.sh` | Video chat roulette |
| `pocketbase.sh` | Go backend with built-in SQLite database, authentication, file storage and admin dashboard |

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

| Variable | Description | Default |
|----------|-------------|---------|
| `SCRIPTS_DIR` | Directory with scripts | `../scripts` |
| `DATA_DIR` | Directory with data files | `..` |
| `SCRIPTS_BASE_URL` | Base URL for downloading scripts | `https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts` |

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

**Headers:**
```
Content-Type: application/json
```

**Request Body:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `script_name` | string | Yes | Name of the script to execute |
| `server_ip` | string | Yes | IP address of the remote server |
| `server_root_password` | string | Yes | Root password for SSH |
| `additional` | string | No | Additional parameters for the script (e.g., domain name) |

**Example Request:**
```bash
curl -X POST http://localhost:5000/api/install \
  -H "Content-Type: application/json" \
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
| 403 | Access denied |
| 404 | Resource not found |
| 500 | Internal server error |
| 503 | Service unavailable (paramiko library not installed) |

## Script Requirements

Detailed requirements for scripts are described in [requirements_for_scripts_ru.md](requirements_for_scripts_ru.md) (in Russian).

## License

MIT
