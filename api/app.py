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
import hashlib
import threading
from typing import Optional
from functools import wraps
from flask import Flask, jsonify, request
from dotenv import load_dotenv
from rate_limiter import RateLimiter

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

# Tasks directory for storing task reports
TASKS_DIR = os.environ.get('TASKS_DIR', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tasks'))

# Ensure tasks directory exists
os.makedirs(TASKS_DIR, exist_ok=True)

# Task status constants
TASK_STATUS_PROCESSING = 'processing'
TASK_STATUS_COMPLETED = 'completed'
TASK_STATUS_ERROR = 'error'

# API Key configuration
API_KEY = os.environ.get('API_KEY', '')

# Protection/Rate Limiting configuration
PROTECTION_ENABLED = os.environ.get('PROTECTION_ENABLED', 'true').lower() in ('true', '1', 'yes')
RATE_LIMIT_MAX_REQUESTS = int(os.environ.get('RATE_LIMIT_MAX_REQUESTS', '10'))
RATE_LIMIT_TIME_WINDOW = int(os.environ.get('RATE_LIMIT_TIME_WINDOW', '60'))
RATE_LIMITER_DB_PATH = os.environ.get(
    'RATE_LIMITER_DB_PATH',
    os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rate_limiter.db')
)

# Configure logging
logger = logging.getLogger(__name__)

# Initialize rate limiter
rate_limiter = RateLimiter(
    db_path=RATE_LIMITER_DB_PATH,
    max_requests=RATE_LIMIT_MAX_REQUESTS,
    time_window=RATE_LIMIT_TIME_WINDOW,
    enabled=PROTECTION_ENABLED
)


def generate_task_id(script_name, server_ip, server_root_password, additional=''):
    """
    Generate a unique task ID based on MD5 hash of all input parameters.

    Args:
        script_name: Name of the script to execute
        server_ip: IP address of the remote server
        server_root_password: Root password for SSH authentication
        additional: Additional parameters to pass to the script

    Returns:
        str: MD5 hash string to be used as task_id
    """
    data = f"{script_name}:{server_ip}:{server_root_password}:{additional}"
    return hashlib.md5(data.encode('utf-8')).hexdigest()


def strip_ansi_codes(text: Optional[str]) -> Optional[str]:
    """
    Strip ANSI escape codes from text.

    Removes all ANSI escape sequences including:
    - Color codes (e.g., \\033[31m for red, \\033[0m for reset)
    - Cursor movement codes
    - Screen clear codes
    - Other terminal control sequences

    Args:
        text: String that may contain ANSI escape sequences

    Returns:
        str: Clean text with all ANSI escape sequences removed,
             or None/empty string if input is None/empty
    """
    if not text:
        return text

    # Pattern matches all ANSI escape sequences:
    # - \x1b: ESC character
    # - \[: CSI (Control Sequence Introducer)
    # - [0-9;]*: Optional numeric parameters separated by semicolons
    # - [A-Za-z]: Command character (m for color, H for cursor, etc.)
    # Also matches OSC (Operating System Command) sequences: ESC ] ... BEL/ST
    ansi_pattern = re.compile(
        r'\x1b'           # ESC character
        r'(?:'            # Non-capturing group for alternatives
        r'\[[0-9;]*[A-Za-z]'  # CSI sequences (colors, cursor, etc.)
        r'|'              # OR
        r'\][^\x07]*\x07' # OSC sequences ending with BEL
        r'|'              # OR
        r'\][^\x1b]*\x1b\\' # OSC sequences ending with ST (ESC \)
        r'|'              # OR
        r'[PX^_][^\x1b]*\x1b\\' # DCS, SOS, PM, APC sequences
        r'|'              # OR
        r'[NOc]'          # Single character sequences (SS2, SS3, RIS)
        r')'
    )
    return ansi_pattern.sub('', text)


def get_task_file_path(task_id):
    """
    Get the full path to the task report file.

    Args:
        task_id: The task ID

    Returns:
        str: Full path to the task report file
    """
    return os.path.join(TASKS_DIR, f"{task_id}.txt")


def write_task_status(task_id, status, content=''):
    """
    Write task status and content to the task report file.

    ANSI escape codes (colors, cursor control, etc.) are automatically
    stripped from the content to ensure clean, readable text in the report.

    Args:
        task_id: The task ID
        status: Current status (processing, completed, error)
        content: Content to append to the report
    """
    task_file = get_task_file_path(task_id)
    # Strip ANSI escape codes from content for clean text output
    clean_content = strip_ansi_codes(content) if content else ''
    with open(task_file, 'w', encoding='utf-8') as f:
        f.write(f"STATUS:{status}\n")
        f.write(clean_content)


def append_task_content(task_id, content):
    """
    Append content to the task report file without changing status.

    ANSI escape codes (colors, cursor control, etc.) are automatically
    stripped from the content to ensure clean, readable text in the report.

    Args:
        task_id: The task ID
        content: Content to append to the report
    """
    task_file = get_task_file_path(task_id)
    # Strip ANSI escape codes from content for clean text output
    clean_content = strip_ansi_codes(content) if content else ''
    with open(task_file, 'a', encoding='utf-8') as f:
        f.write(clean_content)


def read_task_status(task_id):
    """
    Read the task status and content from the report file.

    Args:
        task_id: The task ID

    Returns:
        tuple: (status, content) or (None, None) if not found
    """
    task_file = get_task_file_path(task_id)
    if not os.path.exists(task_file):
        return None, None

    with open(task_file, 'r', encoding='utf-8') as f:
        content = f.read()

    # Parse status from the first line
    lines = content.split('\n', 1)
    if lines and lines[0].startswith('STATUS:'):
        status = lines[0].replace('STATUS:', '').strip()
        result_content = lines[1] if len(lines) > 1 else ''
        return status, result_content

    return None, None


def delete_task_file(task_id):
    """
    Delete the task report file.

    Args:
        task_id: The task ID
    """
    task_file = get_task_file_path(task_id)
    if os.path.exists(task_file):
        os.remove(task_file)


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


def get_client_ip():
    """
    Get the real client IP address from the request.

    Handles cases where the API is behind a reverse proxy by checking
    X-Forwarded-For and X-Real-IP headers first.

    Returns:
        str: Client IP address
    """
    # Check X-Forwarded-For header (set by reverse proxies)
    if request.headers.get('X-Forwarded-For'):
        # X-Forwarded-For can contain multiple IPs, take the first one (original client)
        return request.headers.get('X-Forwarded-For').split(',')[0].strip()

    # Check X-Real-IP header (set by some reverse proxies like nginx)
    if request.headers.get('X-Real-IP'):
        return request.headers.get('X-Real-IP')

    # Fall back to direct remote address
    return request.remote_addr


def check_rate_limit(f):
    """
    Decorator to check rate limit for the /api/install endpoint.

    Records the request and checks if the IP has exceeded the rate limit.
    If rate limit is exceeded, returns 429 Too Many Requests.
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Skip if protection is disabled
        if not rate_limiter.enabled:
            return f(*args, **kwargs)

        client_ip = get_client_ip()
        endpoint = request.path

        # Check if IP is blocked and record request
        allowed, count, reason = rate_limiter.record_request(client_ip, endpoint)

        if not allowed:
            logger.warning(f"Rate limit: IP {client_ip} blocked - {reason}")
            return jsonify({
                'success': False,
                'error': f'Access denied: {reason}',
                'ip': client_ip,
                'requests_count': count
            }), 429

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
@require_api_key
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
@require_api_key
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


def execute_script_via_ssh_async(task_id, server_ip, server_root_password, script_name, additional=None, port=SSH_DEFAULT_PORT):
    """
    Execute an installation script on a remote server via SSH in a background thread.

    This function streams output to a task report file and updates the status
    when the execution completes.

    Args:
        task_id: The task ID for tracking this execution
        server_ip: IP address of the remote server
        server_root_password: Root password for SSH authentication
        script_name: Name of the script to execute (without .sh extension)
        additional: Optional additional parameters to pass to the script
        port: SSH port (default: 22)
    """
    if not SSH_AVAILABLE:
        write_task_status(task_id, TASK_STATUS_ERROR, 'SSH library (paramiko) is not installed')
        return

    ssh_client = None
    try:
        # Create SSH client
        ssh_client = paramiko.SSHClient()
        ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        logger.info(f"[Task {task_id}] Connecting to {server_ip}:{port} via SSH...")
        append_task_content(task_id, f"Connecting to {server_ip}:{port} via SSH...\n")

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
        script_url = f"{SCRIPTS_BASE_URL}/{script_name}.sh"

        if additional:
            escaped_additional = additional.replace("'", "'\"'\"'")
            command = f"curl -fsSL -o- {script_url} | bash -s -- '{escaped_additional}'"
        else:
            command = f"curl -fsSL -o- {script_url} | bash"

        logger.info(f"[Task {task_id}] Executing command: {command}")
        append_task_content(task_id, f"Executing script: {script_name}\n")

        # Execute the command
        stdin, stdout, stderr = ssh_client.exec_command(command, get_pty=True)

        # Stream output to the task file
        output_buffer = []
        while True:
            line = stdout.readline()
            if not line:
                break
            decoded_line = line if isinstance(line, str) else line.decode('utf-8', errors='replace')
            output_buffer.append(decoded_line)
            append_task_content(task_id, decoded_line)

        # Read any remaining stderr
        error_output = stderr.read().decode('utf-8', errors='replace')
        if error_output:
            append_task_content(task_id, f"\n{error_output}")

        # Get exit status
        exit_status = stdout.channel.recv_exit_status()

        # Read current content and update status
        _, current_content = read_task_status(task_id)

        if exit_status != 0:
            error_msg = f'\nScript exited with status {exit_status}'
            write_task_status(task_id, TASK_STATUS_ERROR, (current_content or '') + error_msg)
            logger.warning(f"[Task {task_id}] Installation failed with exit status {exit_status}")
        else:
            write_task_status(task_id, TASK_STATUS_COMPLETED, current_content or '')
            logger.info(f"[Task {task_id}] Installation completed successfully")

    except paramiko.AuthenticationException:
        _, current_content = read_task_status(task_id)
        error_msg = '\nSSH authentication failed. Please check the password.'
        write_task_status(task_id, TASK_STATUS_ERROR, (current_content or '') + error_msg)
        logger.error(f"[Task {task_id}] SSH authentication failed")
    except paramiko.SSHException as e:
        _, current_content = read_task_status(task_id)
        error_msg = f'\nSSH connection error: {str(e)}'
        write_task_status(task_id, TASK_STATUS_ERROR, (current_content or '') + error_msg)
        logger.error(f"[Task {task_id}] SSH connection error: {str(e)}")
    except TimeoutError:
        _, current_content = read_task_status(task_id)
        error_msg = f'\nConnection to {server_ip} timed out'
        write_task_status(task_id, TASK_STATUS_ERROR, (current_content or '') + error_msg)
        logger.error(f"[Task {task_id}] Connection timed out")
    except Exception as e:
        _, current_content = read_task_status(task_id)
        error_msg = f'\nUnexpected error: {str(e)}'
        write_task_status(task_id, TASK_STATUS_ERROR, (current_content or '') + error_msg)
        logger.error(f"[Task {task_id}] Unexpected error: {str(e)}")
    finally:
        if ssh_client:
            ssh_client.close()


@app.route('/api/install', methods=['POST'])
@require_api_key
@check_rate_limit
def install():
    """
    Start an installation script on a remote server via SSH in a background thread.

    Requires API key authentication if API_KEY is set in environment.

    POST Parameters (JSON body):
        script_name: Name of the script to execute (required)
        server_ip: IP address of the remote server (required)
        server_root_password: Root password for SSH authentication (required)
        additional: Additional parameters to pass to the script (optional)

    Returns:
        JSON response with:
        - success: True if task was started successfully
        - task_id: The task ID for tracking the installation status
        - error: Error message if something went wrong
    """
    # Check if SSH library is available
    if not SSH_AVAILABLE:
        return jsonify({
            'success': False,
            'error': 'SSH library (paramiko) is not installed. Please install it with: pip install paramiko',
            'task_id': None
        }), 503

    try:
        # Get JSON data from request
        data = request.get_json(silent=True)

        if data is None:
            return jsonify({
                'success': False,
                'error': 'Request body must be JSON',
                'task_id': None
            }), 400

        # Validate required fields
        required_fields = ['script_name', 'server_ip', 'server_root_password']
        missing_fields = [field for field in required_fields if not data.get(field)]

        if missing_fields:
            return jsonify({
                'success': False,
                'error': f'Missing required fields: {", ".join(missing_fields)}',
                'task_id': None
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
                'task_id': None
            }), 400

        # Validate server_ip format (basic check)
        ip_pattern = re.compile(r'^(\d{1,3}\.){3}\d{1,3}$')
        if not ip_pattern.match(server_ip):
            return jsonify({
                'success': False,
                'error': 'Invalid server_ip format. Please provide a valid IPv4 address.',
                'task_id': None
            }), 400

        # Generate task ID based on all input parameters
        task_id = generate_task_id(script_name, server_ip, server_root_password, additional)

        # Check if a task with this ID already exists and is still processing
        existing_status, _ = read_task_status(task_id)
        if existing_status == TASK_STATUS_PROCESSING:
            return jsonify({
                'success': True,
                'task_id': task_id,
                'message': 'Task already in progress'
            })

        # Create task file with initial processing status
        write_task_status(task_id, TASK_STATUS_PROCESSING, f"Starting installation of '{script_name}' on {server_ip}...\n")

        # Start the installation in a background thread
        logger.info(f"Starting installation task {task_id} for '{script_name}' on {server_ip}")
        thread = threading.Thread(
            target=execute_script_via_ssh_async,
            args=(task_id, server_ip, server_root_password, script_name, additional),
            daemon=True
        )
        thread.start()

        return jsonify({
            'success': True,
            'task_id': task_id,
            'message': 'Installation started'
        })

    except Exception as e:
        logger.error(f"Unexpected error in /api/install: {str(e)}")
        return jsonify({
            'success': False,
            'error': f'Unexpected error: {str(e)}',
            'task_id': None
        }), 500


@app.route('/api/status/<task_id>', methods=['GET'])
@require_api_key
def get_task_status(task_id):
    """
    Get the status and output of an installation task.

    Requires API key authentication if API_KEY is set in environment.

    URL Parameters:
        task_id: The task ID returned from /api/install endpoint

    Returns:
        JSON response with:
        - success: True if task was found
        - status: Current status (processing, completed, error)
        - result: Current content of the report file
        - error: Error message if task was not found

    Note:
        When a completed or error task is retrieved, the task file is deleted
        and subsequent requests for the same task_id will return "Task not found".
    """
    try:
        # Validate task_id format (should be MD5 hash - 32 hex characters)
        if not task_id or not re.match(r'^[a-f0-9]{32}$', task_id):
            return jsonify({
                'success': False,
                'error': 'Invalid task_id format',
                'status': None,
                'result': None
            }), 400

        # Read task status and content
        status, content = read_task_status(task_id)

        if status is None:
            return jsonify({
                'success': False,
                'error': 'Task not found',
                'status': None,
                'result': None
            }), 404

        # Strip any remaining ANSI escape codes from content
        # (content should already be clean, but this ensures backward compatibility)
        clean_content = strip_ansi_codes(content) if content else content

        response = {
            'success': True,
            'status': status,
            'result': clean_content
        }

        # If task is completed or has an error, delete the file after returning
        if status in (TASK_STATUS_COMPLETED, TASK_STATUS_ERROR):
            delete_task_file(task_id)

        return jsonify(response)

    except Exception as e:
        logger.error(f"Unexpected error in /api/status/{task_id}: {str(e)}")
        return jsonify({
            'success': False,
            'error': f'Unexpected error: {str(e)}',
            'status': None,
            'result': None
        }), 500


@app.route('/api/protection/status', methods=['GET'])
@require_api_key
def protection_status():
    """
    Get the current status of the protection/rate limiting system.

    Requires API key authentication if API_KEY is set in environment.

    Returns:
        JSON response with protection status and configuration.
    """
    return jsonify({
        'success': True,
        'protection': {
            'enabled': rate_limiter.enabled,
            'max_requests': RATE_LIMIT_MAX_REQUESTS,
            'time_window_seconds': RATE_LIMIT_TIME_WINDOW,
            'blocked_ips_count': len(rate_limiter.get_blocked_ips()) if rate_limiter.enabled else 0
        }
    })


@app.route('/api/protection/blocked', methods=['GET'])
@require_api_key
def get_blocked_ips():
    """
    Get list of all currently blocked IP addresses.

    Requires API key authentication if API_KEY is set in environment.

    Returns:
        JSON response with list of blocked IPs and their details.
    """
    if not rate_limiter.enabled:
        return jsonify({
            'success': False,
            'error': 'Protection mode is disabled',
            'blocked_ips': []
        })

    blocked = rate_limiter.get_blocked_ips()
    return jsonify({
        'success': True,
        'count': len(blocked),
        'blocked_ips': blocked
    })


@app.route('/api/protection/block', methods=['POST'])
@require_api_key
def block_ip():
    """
    Manually block an IP address.

    Requires API key authentication if API_KEY is set in environment.

    POST Parameters (JSON body):
        ip: IP address to block (required)
        reason: Reason for blocking (optional)
        permanent: Whether to block permanently (optional, default: false)
        duration_hours: Duration of block in hours (optional, default: 1)

    Returns:
        JSON response indicating success or failure.
    """
    if not rate_limiter.enabled:
        return jsonify({
            'success': False,
            'error': 'Protection mode is disabled'
        }), 400

    data = request.get_json(silent=True)

    if data is None:
        return jsonify({
            'success': False,
            'error': 'Request body must be JSON'
        }), 400

    ip_address = data.get('ip')

    if not ip_address:
        return jsonify({
            'success': False,
            'error': 'Missing required field: ip'
        }), 400

    # Validate IP format
    ip_pattern = re.compile(r'^(\d{1,3}\.){3}\d{1,3}$')
    if not ip_pattern.match(ip_address):
        return jsonify({
            'success': False,
            'error': 'Invalid IP address format'
        }), 400

    reason = data.get('reason', 'Manual block')
    permanent = data.get('permanent', False)
    duration_hours = data.get('duration_hours', 1)

    success = rate_limiter.block_ip(
        ip_address=ip_address,
        reason=reason,
        permanent=permanent,
        duration_hours=duration_hours
    )

    if success:
        return jsonify({
            'success': True,
            'message': f'IP {ip_address} has been blocked'
        })
    else:
        return jsonify({
            'success': False,
            'error': 'Failed to block IP'
        }), 500


@app.route('/api/protection/unblock', methods=['POST'])
@require_api_key
def unblock_ip():
    """
    Unblock an IP address.

    Requires API key authentication if API_KEY is set in environment.

    POST Parameters (JSON body):
        ip: IP address to unblock (required)

    Returns:
        JSON response indicating success or failure.
    """
    if not rate_limiter.enabled:
        return jsonify({
            'success': False,
            'error': 'Protection mode is disabled'
        }), 400

    data = request.get_json(silent=True)

    if data is None:
        return jsonify({
            'success': False,
            'error': 'Request body must be JSON'
        }), 400

    ip_address = data.get('ip')

    if not ip_address:
        return jsonify({
            'success': False,
            'error': 'Missing required field: ip'
        }), 400

    success = rate_limiter.unblock_ip(ip_address)

    if success:
        return jsonify({
            'success': True,
            'message': f'IP {ip_address} has been unblocked'
        })
    else:
        return jsonify({
            'success': False,
            'error': f'IP {ip_address} was not blocked'
        }), 404


@app.route('/api/protection/stats', methods=['GET'])
@require_api_key
def get_request_stats():
    """
    Get request statistics.

    Requires API key authentication if API_KEY is set in environment.

    Query Parameters:
        ip: Optional IP address to filter by
        limit: Maximum number of records (default: 100)

    Returns:
        JSON response with request statistics.
    """
    if not rate_limiter.enabled:
        return jsonify({
            'success': False,
            'error': 'Protection mode is disabled',
            'stats': []
        })

    ip_address = request.args.get('ip')
    limit = int(request.args.get('limit', 100))

    stats = rate_limiter.get_request_stats(ip_address=ip_address, limit=limit)

    return jsonify({
        'success': True,
        'count': len(stats),
        'stats': stats
    })


@app.route('/health', methods=['GET'])
@require_api_key
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
@require_api_key
def index():
    """
    Root endpoint with API information.

    Returns:
        JSON response with API info and available endpoints.
    """
    return jsonify({
        'name': 'Install Scripts API',
        'version': '1.2.0',
        'endpoints': {
            '/': 'API information (this page)',
            '/health': 'Health check endpoint',
            '/api/scripts_list': 'List all available installation scripts (supports ?lang=ru|en)',
            '/api/script/<script_name>': 'Get information about a single script by script_name (supports ?lang=ru|en)',
            '/api/install': 'Start an installation script in background (POST: script_name, server_ip, server_root_password, additional) - returns task_id',
            '/api/status/<task_id>': 'Get installation task status and result (processing, completed, error)',
            '/api/protection/status': 'Get protection/rate limiting status and configuration',
            '/api/protection/blocked': 'List all currently blocked IP addresses',
            '/api/protection/block': 'Manually block an IP address (POST: ip, reason, permanent, duration_hours)',
            '/api/protection/unblock': 'Unblock an IP address (POST: ip)',
            '/api/protection/stats': 'Get request statistics (supports ?ip=x.x.x.x&limit=N)'
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
