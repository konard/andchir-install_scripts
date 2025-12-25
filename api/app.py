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
import json
import argparse
from flask import Flask, jsonify, request

app = Flask(__name__)

# Configuration
SCRIPTS_DIR = os.environ.get('SCRIPTS_DIR', os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'scripts'))
DATA_DIR = os.environ.get('DATA_DIR', os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_LANG = 'ru'


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
            '/api/script/<script_name>': 'Get information about a single script by script_name (supports ?lang=ru|en)'
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
