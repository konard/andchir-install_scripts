#!/usr/bin/env python3
"""
Test script for Flask API

This script tests the Flask API endpoints locally.
Run this script from the repository root directory.
"""

import os
import sys
import unittest

# Add the api directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'api'))

from app import app, parse_args


class TestParseArgs(unittest.TestCase):
    """Test cases for command-line argument parsing."""

    def test_parse_args_defaults(self):
        """Test that default arguments are set correctly."""
        # Test with empty arguments (default values)
        import sys
        original_argv = sys.argv
        sys.argv = ['app.py']
        try:
            args = parse_args()
            self.assertEqual(args.port, 5000)
            self.assertEqual(args.host, '0.0.0.0')
            self.assertTrue(args.debug)
            self.assertFalse(args.no_debug)
        finally:
            sys.argv = original_argv

    def test_parse_args_custom_port(self):
        """Test that custom port argument is parsed correctly."""
        import sys
        original_argv = sys.argv
        sys.argv = ['app.py', '--port', '8080']
        try:
            args = parse_args()
            self.assertEqual(args.port, 8080)
        finally:
            sys.argv = original_argv

    def test_parse_args_custom_host(self):
        """Test that custom host argument is parsed correctly."""
        import sys
        original_argv = sys.argv
        sys.argv = ['app.py', '--host', '127.0.0.1']
        try:
            args = parse_args()
            self.assertEqual(args.host, '127.0.0.1')
        finally:
            sys.argv = original_argv

    def test_parse_args_no_debug(self):
        """Test that --no-debug argument works correctly."""
        import sys
        original_argv = sys.argv
        sys.argv = ['app.py', '--no-debug']
        try:
            args = parse_args()
            self.assertTrue(args.no_debug)
        finally:
            sys.argv = original_argv

    def test_parse_args_combined(self):
        """Test that multiple arguments can be combined."""
        import sys
        original_argv = sys.argv
        sys.argv = ['app.py', '--port', '3000', '--host', 'localhost', '--no-debug']
        try:
            args = parse_args()
            self.assertEqual(args.port, 3000)
            self.assertEqual(args.host, 'localhost')
            self.assertTrue(args.no_debug)
        finally:
            sys.argv = original_argv


class TestFlaskAPI(unittest.TestCase):
    """Test cases for Flask API endpoints."""

    def setUp(self):
        """Set up test client."""
        self.app = app
        self.app.config['TESTING'] = True
        self.client = self.app.test_client()

    def test_index_endpoint(self):
        """Test the root endpoint returns API info."""
        response = self.client.get('/')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data['name'], 'Install Scripts API')
        self.assertIn('endpoints', data)

    def test_health_endpoint(self):
        """Test the health endpoint returns healthy status."""
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data['status'], 'healthy')

    def test_scripts_list_endpoint(self):
        """Test the scripts_list endpoint returns list of scripts."""
        response = self.client.get('/api/scripts_list')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertTrue(data['success'])
        self.assertIn('scripts', data)
        self.assertIn('count', data)
        # Should have at least 2 scripts (Django and Flask installer)
        self.assertGreaterEqual(len(data['scripts']), 1)

    def test_scripts_list_contains_expected_scripts(self):
        """Test that scripts_list contains expected installation scripts."""
        response = self.client.get('/api/scripts_list')
        data = response.get_json()
        script_names = [s['script_name'] for s in data['scripts']]
        # Check that our installation scripts are present
        self.assertIn('various-useful-api-django', script_names)
        self.assertIn('install-scripts-api-flask', script_names)

    def test_scripts_list_names_without_extension(self):
        """Test that script names are returned without file extensions."""
        response = self.client.get('/api/scripts_list')
        data = response.get_json()
        script_names = [s['script_name'] for s in data['scripts']]
        # Verify that no script names contain file extensions
        for script_name in script_names:
            self.assertNotIn('.sh', script_name, f"Script name '{script_name}' should not contain extension")

    def test_get_script_endpoint(self):
        """Test the /api/script/<script_name> endpoint returns script info."""
        response = self.client.get('/api/script/various-useful-api-django')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertTrue(data['success'])
        self.assertIn('result', data)
        self.assertEqual(data['result']['script_name'], 'various-useful-api-django')

    def test_get_script_not_found(self):
        """Test that /api/script/<script_name> returns 404 for non-existent script."""
        response = self.client.get('/api/script/non-existent-script')
        self.assertEqual(response.status_code, 404)
        data = response.get_json()
        self.assertFalse(data['success'])
        self.assertIn('error', data)
        self.assertIsNone(data['result'])

    def test_get_script_with_lang_param(self):
        """Test the /api/script/<script_name> endpoint with lang parameter."""
        # Test with English
        response = self.client.get('/api/script/various-useful-api-django?lang=en')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertTrue(data['success'])
        self.assertIn('result', data)
        # English description should contain "A collection of useful APIs"
        self.assertIn('A collection of useful APIs', data['result']['description'])

        # Test with Russian (default)
        response = self.client.get('/api/script/various-useful-api-django?lang=ru')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertTrue(data['success'])
        # Russian description should contain "Набор полезных API"
        self.assertIn('Набор полезных API', data['result']['description'])

    def test_get_script_all_scripts(self):
        """Test that all scripts in data file can be retrieved individually."""
        # Get all scripts first
        response = self.client.get('/api/scripts_list')
        data = response.get_json()
        scripts = data['scripts']

        # Test each script can be retrieved
        for script in scripts:
            script_name = script['script_name']
            response = self.client.get(f'/api/script/{script_name}')
            self.assertEqual(response.status_code, 200, f"Failed to get script: {script_name}")
            script_data = response.get_json()
            self.assertTrue(script_data['success'])
            self.assertEqual(script_data['result']['script_name'], script_name)


if __name__ == '__main__':
    unittest.main(verbosity=2)
