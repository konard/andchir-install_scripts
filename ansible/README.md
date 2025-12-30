# Ansible Playbooks

Ansible playbooks for automated software installation.

## Requirements

- Python 3.12+
- Ansible 10.0.0+

## Installation

```bash
# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate

# Install Ansible
pip install -r requirements.txt
```

## Available Playbooks

### playbooks/n8n.yml

Installs n8n workflow automation platform with PostgreSQL database.

**Components installed:**
- Docker and Docker Compose
- PostgreSQL 16 (via Docker)
- n8n (via Docker)
- Nginx (reverse proxy)
- SSL certificate via Let's Encrypt

**Usage:**

1. Copy the inventory file and configure your servers:
   ```bash
   cp inventory.ini.example inventory.ini
   # Edit inventory.ini with your server details
   ```

2. Run the playbook:
   ```bash
   ansible-playbook -i inventory.ini playbooks/n8n.yml -e "domain_name=n8n.example.com"
   ```

**Variables:**
- `domain_name` (required) - Domain name for n8n (e.g., n8n.example.com)

## Directory Structure

```
ansible/
├── README.md                    # This file
├── requirements.txt             # Python dependencies
├── inventory.ini.example        # Example inventory file
├── playbooks/                   # Ansible playbooks
│   └── n8n.yml                 # n8n installation playbook
└── templates/                   # Jinja2 templates
    ├── n8n.env.j2              # Environment variables template
    ├── n8n.docker-compose.yml.j2  # Docker Compose template
    ├── n8n.nginx.conf.j2       # Nginx configuration template
    └── n8n.manage.sh.j2        # Management script template
```
