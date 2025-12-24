#!/usr/bin/env python3
"""
Flask API Application for Install Scripts

This API provides endpoints to manage and list installation scripts.
"""

import os
from flask import Flask, jsonify

app = Flask(__name__)

# Configuration
SCRIPTS_DIR = os.environ.get('SCRIPTS_DIR', os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'scripts'))


@app.route('/api/scripts_list', methods=['GET'])
def scripts_list():
    """
    List all scripts in the scripts directory.

    Returns:
        JSON response with list of script filenames and their details.
    """
    try:
        if not os.path.exists(SCRIPTS_DIR):
            return jsonify({
                'success': False,
                'error': 'Scripts directory not found',
                'scripts': []
            }), 404

        scripts = []
        for filename in os.listdir(SCRIPTS_DIR):
            filepath = os.path.join(SCRIPTS_DIR, filename)
            if os.path.isfile(filepath):
                scripts.append({
                    'name': filename,
                    'size': os.path.getsize(filepath),
                    'path': filepath
                })

        # Sort scripts by name
        scripts.sort(key=lambda x: x['name'])

        return jsonify({
            'success': True,
            'count': len(scripts),
            'scripts': scripts
        })

    except PermissionError:
        return jsonify({
            'success': False,
            'error': 'Permission denied accessing scripts directory',
            'scripts': []
        }), 403
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'scripts': []
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
            '/api/scripts_list': 'List all available installation scripts'
        }
    })


if __name__ == '__main__':
    # Development server
    app.run(host='0.0.0.0', port=5000, debug=True)
