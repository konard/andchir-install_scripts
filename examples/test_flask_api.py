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

from app import app


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
        script_names = [s['name'] for s in data['scripts']]
        # Check that our installation scripts are present
        self.assertIn('various-useful-api-django.sh', script_names)
        self.assertIn('install-scripts-api-flask.sh', script_names)


if __name__ == '__main__':
    unittest.main(verbosity=2)
