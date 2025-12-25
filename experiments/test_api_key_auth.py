#!/usr/bin/env python3
"""
Test script for API key authentication functionality.
"""

import os
import sys
import unittest
from unittest.mock import patch

# Add the api directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'api'))

# Import with no API key set
os.environ.pop('API_KEY', None)
import app as app_module


class TestApiKeyAuth(unittest.TestCase):
    """Test cases for API key authentication."""

    def setUp(self):
        """Set up test client."""
        self.app = app_module.app
        self.app.testing = True
        self.client = self.app.test_client()

    def test_install_without_api_key_when_disabled(self):
        """Test /api/install without API key when API_KEY is not set."""
        # When API_KEY is not set, authentication should be disabled
        with patch.object(app_module, 'API_KEY', ''):
            response = self.client.post('/api/install',
                                        json={'script_name': 'test',
                                              'server_ip': '192.168.1.1',
                                              'server_root_password': 'test'})
            # Should get 503 (no paramiko) or success, but not 401
            self.assertNotEqual(response.status_code, 401)

    def test_install_without_api_key_when_required(self):
        """Test /api/install without API key when API_KEY is set."""
        with patch.object(app_module, 'API_KEY', 'test-secret-key'):
            response = self.client.post('/api/install',
                                        json={'script_name': 'test',
                                              'server_ip': '192.168.1.1',
                                              'server_root_password': 'test'})
            self.assertEqual(response.status_code, 401)
            data = response.get_json()
            self.assertFalse(data['success'])
            self.assertIn('API key is required', data['error'])

    def test_install_with_wrong_api_key(self):
        """Test /api/install with wrong API key."""
        with patch.object(app_module, 'API_KEY', 'correct-key'):
            response = self.client.post('/api/install',
                                        json={'script_name': 'test',
                                              'server_ip': '192.168.1.1',
                                              'server_root_password': 'test'},
                                        headers={'X-API-Key': 'wrong-key'})
            self.assertEqual(response.status_code, 401)
            data = response.get_json()
            self.assertFalse(data['success'])
            self.assertIn('Invalid API key', data['error'])

    def test_install_with_correct_api_key_in_header(self):
        """Test /api/install with correct API key in header."""
        with patch.object(app_module, 'API_KEY', 'test-secret-key'):
            response = self.client.post('/api/install',
                                        json={'script_name': 'test',
                                              'server_ip': '192.168.1.1',
                                              'server_root_password': 'test'},
                                        headers={'X-API-Key': 'test-secret-key'})
            # Should not be 401 (authentication passed)
            self.assertNotEqual(response.status_code, 401)
            # Might be 503 (paramiko not available) which is expected

    def test_install_with_correct_api_key_in_query_param(self):
        """Test /api/install with correct API key in query parameter."""
        with patch.object(app_module, 'API_KEY', 'test-secret-key'):
            response = self.client.post('/api/install?api_key=test-secret-key',
                                        json={'script_name': 'test',
                                              'server_ip': '192.168.1.1',
                                              'server_root_password': 'test'})
            # Should not be 401 (authentication passed)
            self.assertNotEqual(response.status_code, 401)

    def test_scripts_list_no_auth_required(self):
        """Test that /api/scripts_list doesn't require authentication."""
        with patch.object(app_module, 'API_KEY', 'test-secret-key'):
            response = self.client.get('/api/scripts_list')
            # Should not be 401 - no auth required for read endpoints
            self.assertNotEqual(response.status_code, 401)

    def test_health_no_auth_required(self):
        """Test that /health doesn't require authentication."""
        with patch.object(app_module, 'API_KEY', 'test-secret-key'):
            response = self.client.get('/health')
            self.assertEqual(response.status_code, 200)

    def test_index_no_auth_required(self):
        """Test that / doesn't require authentication."""
        with patch.object(app_module, 'API_KEY', 'test-secret-key'):
            response = self.client.get('/')
            self.assertEqual(response.status_code, 200)


if __name__ == '__main__':
    unittest.main(verbosity=2)
