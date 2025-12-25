#!/usr/bin/env python3
"""
Flask API Application for Install Scripts

This API provides endpoints to manage and list installation scripts.

Usage:
    python app.py [--port PORT] [--host HOST]

Arguments:
    --port PORT  Port to run the server on (default: 5000)
    --host HOST  Host to bind the server to (default: 0.0.0.0)
"""

import os
import re
import json
import argparse
import logging
from functools import wraps
from flask import Flask, jsonify, request
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# SSH imports - optional, only required for /api/install endpoint
try:
    import paramiko
    SSH_AVAILABLE = True
except ImportError:
    SSH_AVAILABLE = False
    paramiko = None

app = Flask(__name__)

# Configuration
SCRIPTS_DIR = os.environ.get('SCRIPTS_DIR', os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'scripts'))
DATA_DIR = os.environ.get('DATA_DIR', os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_LANG = 'ru'
SCRIPTS_BASE_URL = os.environ.get('SCRIPTS_BASE_URL', 'https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts')
SSH_DEFAULT_PORT = 22
SSH_DEFAULT_TIMEOUT = 30

# API Key configuration
API_KEY = os.environ.get('API_KEY', '')

# Configure logging
logger = logging.getLogger(__name__)


def require_api_key(f):
    """
    Decorator to require API key authentication for an endpoint.

    The API key can be provided in one of the following ways:
    - Header: X-API-Key
    - Query parameter: api_key

    If API_KEY environment variable is not set or empty, authentication is disabled.
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # If API_KEY is not set, skip authentication
        if not API_KEY:
            return f(*args, **kwargs)

        # Check for API key in header
        provided_key = request.headers.get('X-API-Key')

        # If not in header, check query parameter
        if not provided_key:
            provided_key = request.args.get('api_key')

        # Validate the API key
        if not provided_key:
            return jsonify({
                'success': False,
                'error': 'API key is required. Provide it via X-API-Key header or api_key query parameter.'
            }), 401

        if provided_key != API_KEY:
            return jsonify({
                'success': False,
                'error': 'Invalid API key'
            }), 401

        return f(*args, **kwargs)
    return decorated_function


def get_data_file_path(lang):
    """
    Get the path to the data file for the specified language.
    Falls back to default language (ru) if the requested language file doesn't exist.

    Args:
        lang: Language code (e.g., 'ru', 'en')

    Returns:
        Path to the data file
    """
    # Try to get the data file for the requested language
    data_file = os.path.join(DATA_DIR, f'data_{lang}.json')
    if os.path.exists(data_file):
        return data_file

    # Fall back to default language
    return os.path.join(DATA_DIR, f'data_{DEFAULT_LANG}.json')


@app.route('/api/scripts_list', methods=['GET'])
def scripts_list():
    """
    List all scripts from the data file.

    Query Parameters:
        lang: Language code for the data file (default: 'ru')
              Falls back to 'ru' if the requested language file doesn't exist.

    Returns:
        JSON response with list of scripts and their details from the data file.
    """
    try:
        # Get language from query parameter, default to 'ru'
        lang = request.args.get('lang', DEFAULT_LANG)

        # Get the appropriate data file path
        data_file_path = get_data_file_path(lang)

        if not os.path.exists(data_file_path):
            return jsonify({
                'success': False,
                'error': 'Data file not found',
                'scripts': []
            }), 404

        # Load scripts from the data file
        with open(data_file_path, 'r', encoding='utf-8') as f:
            scripts = json.load(f)

        return jsonify({
            'success': True,
            'count': len(scripts),
            'scripts': scripts
        })

    except json.JSONDecodeError as e:
        return jsonify({
            'success': False,
            'error': f'Invalid JSON format in data file: {str(e)}',
            'scripts': []
        }), 500
    except PermissionError:
        return jsonify({
            'success': False,
            'error': 'Permission denied accessing data file',
            'scripts': []
        }), 403
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'scripts': []
        }), 500


@app.route('/api/script/<script_name>', methods=['GET'])
def get_script(script_name):
    """
    Get information about a single script by its script_name.

    URL Parameters:
        script_name: The script_name to look up (e.g., 'various-useful-api-django')

    Query Parameters:
        lang: Language code for the data file (default: 'ru')
              Falls back to 'ru' if the requested language file doesn't exist.

    Returns:
        JSON response with script details if found, or 404 if not found.
    """
    try:
        # Get language from query parameter, default to 'ru'
        lang = request.args.get('lang', DEFAULT_LANG)

        # Get the appropriate data file path
        data_file_path = get_data_file_path(lang)

        if not os.path.exists(data_file_path):
            return jsonify({
                'success': False,
                'error': 'Data file not found',
                'result': None
            }), 404

        # Load scripts from the data file
        with open(data_file_path, 'r', encoding='utf-8') as f:
            scripts = json.load(f)

        # Find the script by script_name
        for script in scripts:
            if script.get('script_name') == script_name:
                return jsonify({
                    'success': True,
                    'result': script
                })

        # Script not found
        return jsonify({
            'success': False,
            'error': f'Script with script_name "{script_name}" not found',
            'result': None
        }), 404

    except json.JSONDecodeError as e:
        return jsonify({
            'success': False,
            'error': f'Invalid JSON format in data file: {str(e)}',
            'result': None
        }), 500
    except PermissionError:
        return jsonify({
            'success': False,
            'error': 'Permission denied accessing data file',
            'result': None
        }), 403
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'result': None
        }), 500


def execute_script_via_ssh(server_ip, server_root_password, script_name, additional=None, port=SSH_DEFAULT_PORT):
    """
    Execute an installation script on a remote server via SSH.

    Connects to the remote server using SSH, downloads and executes the script,
    and returns the output. The script is executed in-memory without leaving
    files on the remote server.

    Args:
        server_ip: IP address of the remote server
        server_root_password: Root password for SSH authentication
        script_name: Name of the script to execute (without .sh extension)
        additional: Optional additional parameters to pass to the script
        port: SSH port (default: 22)

    Returns:
        tuple: (success: bool, output: str, error: str or None)
    """
    if not SSH_AVAILABLE:
        return False, '', 'SSH library (paramiko) is not installed'

    ssh_client = None
    try:
        # Create SSH client
        ssh_client = paramiko.SSHClient()
        ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        logger.info(f"Connecting to {server_ip}:{port} via SSH...")

        # Connect to the server
        ssh_client.connect(
            hostname=server_ip,
            port=port,
            username='root',
            password=server_root_password,
            timeout=SSH_DEFAULT_TIMEOUT,
            look_for_keys=False,
            allow_agent=False
        )

        # Build the command to download and execute the script
        # The script is piped directly to bash without saving to disk
        script_url = f"{SCRIPTS_BASE_URL}/{script_name}.sh"

        if additional:
            # Escape the additional parameter to prevent command injection
            # Use single quotes and escape any single quotes within
            escaped_additional = additional.replace("'", "'\"'\"'")
            command = f"curl -fsSL -o- {script_url} | bash -s -- '{escaped_additional}'"
        else:
            command = f"curl -fsSL -o- {script_url} | bash"

        logger.info(f"Executing command: {command}")

        # Execute the command
        stdin, stdout, stderr = ssh_client.exec_command(command, get_pty=True)

        # Read output
        output = stdout.read().decode('utf-8', errors='replace')
        error_output = stderr.read().decode('utf-8', errors='replace')

        # Get exit status
        exit_status = stdout.channel.recv_exit_status()

        # Combine output
        full_output = output
        if error_output:
            full_output += '\n' + error_output

        if exit_status != 0:
            return False, full_output, f'Script exited with status {exit_status}'

        return True, full_output, None

    except paramiko.AuthenticationException:
        return False, '', 'SSH authentication failed. Please check the password.'
    except paramiko.SSHException as e:
        return False, '', f'SSH connection error: {str(e)}'
    except TimeoutError:
        return False, '', f'Connection to {server_ip} timed out'
    except Exception as e:
        return False, '', f'Unexpected error: {str(e)}'
    finally:
        if ssh_client:
            ssh_client.close()


@app.route('/api/install', methods=['POST'])
@require_api_key
def install():
    """
    Execute an installation script on a remote server via SSH.

    Requires API key authentication if API_KEY is set in environment.

    POST Parameters (JSON body):
        script_name: Name of the script to execute (required)
        server_ip: IP address of the remote server (required)
        server_root_password: Root password for SSH authentication (required)
        additional: Additional parameters to pass to the script (optional)

    Returns:
        JSON response with:
        - success: True if script executed successfully
        - output: The script's output
        - error: Error message if something went wrong
    """
    # Check if SSH library is available
    if not SSH_AVAILABLE:
        return jsonify({
            'success': False,
            'error': 'SSH library (paramiko) is not installed. Please install it with: pip install paramiko',
            'output': ''
        }), 503

    try:
        # Get JSON data from request
        data = request.get_json(silent=True)

        if data is None:
            return jsonify({
                'success': False,
                'error': 'Request body must be JSON',
                'output': ''
            }), 400

        # Validate required fields
        required_fields = ['script_name', 'server_ip', 'server_root_password']
        missing_fields = [field for field in required_fields if not data.get(field)]

        if missing_fields:
            return jsonify({
                'success': False,
                'error': f'Missing required fields: {", ".join(missing_fields)}',
                'output': ''
            }), 400

        script_name = data['script_name']
        server_ip = data['server_ip']
        server_root_password = data['server_root_password']
        additional = data.get('additional', '')

        # Validate script_name format (basic security check)
        if not script_name.replace('-', '').replace('_', '').isalnum():
            return jsonify({
                'success': False,
                'error': 'Invalid script_name format. Only alphanumeric characters, hyphens, and underscores are allowed.',
                'output': ''
            }), 400

        # Validate server_ip format (basic check)
        ip_pattern = re.compile(r'^(\d{1,3}\.){3}\d{1,3}$')
        if not ip_pattern.match(server_ip):
            return jsonify({
                'success': False,
                'error': 'Invalid server_ip format. Please provide a valid IPv4 address.',
                'output': ''
            }), 400

        # Execute the script via SSH
        logger.info(f"Starting installation of '{script_name}' on {server_ip}")
        success, output, error = execute_script_via_ssh(
            server_ip=server_ip,
            server_root_password=server_root_password,
            script_name=script_name,
            additional=additional
        )

        if success:
            logger.info(f"Installation of '{script_name}' on {server_ip} completed successfully")
            return jsonify({
                'success': True,
                'output': output,
                'error': None
            })
        else:
            logger.warning(f"Installation of '{script_name}' on {server_ip} failed: {error}")
            return jsonify({
                'success': False,
                'output': output,
                'error': error
            }), 500

    except Exception as e:
        logger.error(f"Unexpected error in /api/install: {str(e)}")
        return jsonify({
            'success': False,
            'error': f'Unexpected error: {str(e)}',
            'output': ''
        }), 500


@app.route('/health', methods=['GET'])
def health():
    """
    Health check endpoint.

    Returns:
        JSON response indicating the API is running.
    """
    return jsonify({
        'status': 'healthy',
        'message': 'API is running'
    })


@app.route('/', methods=['GET'])
def index():
    """
    Root endpoint with API information.

    Returns:
        JSON response with API info and available endpoints.
    """
    return jsonify({
        'name': 'Install Scripts API',
        'version': '1.0.0',
        'endpoints': {
            '/': 'API information (this page)',
            '/health': 'Health check endpoint',
            '/api/scripts_list': 'List all available installation scripts (supports ?lang=ru|en)',
            '/api/script/<script_name>': 'Get information about a single script by script_name (supports ?lang=ru|en)',
            '/api/install': 'Execute an installation script on a remote server via SSH (POST: script_name, server_ip, server_root_password, additional)'
        }
    })


def parse_args():
    """
    Parse command-line arguments.

    Returns:
        Parsed arguments namespace.
    """
    parser = argparse.ArgumentParser(
        description='Flask API Application for Install Scripts'
    )
    parser.add_argument(
        '--port',
        type=int,
        default=5000,
        help='Port to run the server on (default: 5000)'
    )
    parser.add_argument(
        '--host',
        type=str,
        default='0.0.0.0',
        help='Host to bind the server to (default: 0.0.0.0)'
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        default=True,
        help='Run in debug mode (default: True)'
    )
    parser.add_argument(
        '--no-debug',
        action='store_true',
        help='Disable debug mode'
    )
    return parser.parse_args()


if __name__ == '__main__':
    # Parse command-line arguments
    args = parse_args()
    debug_mode = args.debug and not args.no_debug

    # Development server
    app.run(host=args.host, port=args.port, debug=debug_mode)
