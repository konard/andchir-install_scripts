#!/usr/bin/env python3
"""
Test script for Flask API

This script tests the Flask API endpoints locally.
Run this script from the repository root directory.
"""

import os
import sys
import json
import unittest
from unittest.mock import patch, MagicMock

# Add the api directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'api'))

from app import (
    app, parse_args, execute_script_via_ssh, SSH_AVAILABLE,
    generate_task_id, get_task_file_path, write_task_status, read_task_status,
    delete_task_file, append_task_content, strip_ansi_codes,
    TASK_STATUS_PROCESSING, TASK_STATUS_COMPLETED, TASK_STATUS_ERROR,
    TASKS_DIR
)


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


class TestInstallEndpoint(unittest.TestCase):
    """Test cases for the /api/install endpoint."""

    def setUp(self):
        """Set up test client."""
        self.app = app
        self.app.config['TESTING'] = True
        self.client = self.app.test_client()

    def tearDown(self):
        """Clean up any task files created during tests."""
        import glob
        for f in glob.glob(os.path.join(TASKS_DIR, '*.txt')):
            try:
                os.remove(f)
            except:
                pass

    def test_install_endpoint_missing_body(self):
        """Test that /api/install returns 400 when no JSON body is provided."""
        response = self.client.post('/api/install', content_type='application/json')
        self.assertEqual(response.status_code, 400)
        data = response.get_json()
        self.assertFalse(data['success'])
        self.assertIn('error', data)

    def test_install_endpoint_missing_fields(self):
        """Test that /api/install returns 400 when required fields are missing."""
        # Missing all required fields
        response = self.client.post('/api/install',
                                    data=json.dumps({}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 400)
        data = response.get_json()
        self.assertFalse(data['success'])
        self.assertIn('Missing required fields', data['error'])

        # Missing server_ip and server_root_password
        response = self.client.post('/api/install',
                                    data=json.dumps({'script_name': 'test'}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 400)
        data = response.get_json()
        self.assertFalse(data['success'])
        self.assertIn('server_ip', data['error'])

    def test_install_endpoint_invalid_script_name(self):
        """Test that /api/install returns 400 for invalid script_name format."""
        response = self.client.post('/api/install',
                                    data=json.dumps({
                                        'script_name': 'test; rm -rf /',
                                        'server_ip': '192.168.1.1',
                                        'server_root_password': 'password'
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 400)
        data = response.get_json()
        self.assertFalse(data['success'])
        self.assertIn('Invalid script_name format', data['error'])

    def test_install_endpoint_invalid_ip(self):
        """Test that /api/install returns 400 for invalid IP address."""
        response = self.client.post('/api/install',
                                    data=json.dumps({
                                        'script_name': 'test-script',
                                        'server_ip': 'invalid-ip',
                                        'server_root_password': 'password'
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 400)
        data = response.get_json()
        self.assertFalse(data['success'])
        self.assertIn('Invalid server_ip format', data['error'])

    def test_install_endpoint_valid_script_name_formats(self):
        """Test that script_name validation accepts valid formats."""
        # These should all pass validation and return a task_id
        valid_names = ['test', 'test-script', 'test_script', 'script123']
        for name in valid_names:
            response = self.client.post('/api/install',
                                        data=json.dumps({
                                            'script_name': name,
                                            'server_ip': '192.168.1.1',
                                            'server_root_password': 'password'
                                        }),
                                        content_type='application/json')
            # Should not be 400 for script_name validation
            data = response.get_json()
            if response.status_code == 400:
                self.assertNotIn('Invalid script_name format', data.get('error', ''))

    def test_install_endpoint_returns_task_id(self):
        """Test that /api/install returns a task_id for valid requests."""
        response = self.client.post('/api/install',
                                    data=json.dumps({
                                        'script_name': 'test-script',
                                        'server_ip': '192.168.1.1',
                                        'server_root_password': 'password'
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertTrue(data['success'])
        self.assertIn('task_id', data)
        self.assertIsNotNone(data['task_id'])
        # Verify task_id is a valid MD5 hash (32 hex characters)
        self.assertRegex(data['task_id'], r'^[a-f0-9]{32}$')

    def test_install_endpoint_same_params_same_task_id(self):
        """Test that the same parameters generate the same task_id."""
        params = {
            'script_name': 'test-script',
            'server_ip': '192.168.1.1',
            'server_root_password': 'password',
            'additional': 'extra'
        }

        response1 = self.client.post('/api/install',
                                     data=json.dumps(params),
                                     content_type='application/json')
        data1 = response1.get_json()

        # Clear the task file to allow another request with same params
        if data1.get('task_id'):
            delete_task_file(data1['task_id'])

        response2 = self.client.post('/api/install',
                                     data=json.dumps(params),
                                     content_type='application/json')
        data2 = response2.get_json()

        self.assertEqual(data1['task_id'], data2['task_id'])


class TestExecuteScriptViaSSH(unittest.TestCase):
    """Test cases for the execute_script_via_ssh function."""

    @unittest.skipIf(not SSH_AVAILABLE, "paramiko not installed")
    @patch('app.paramiko.SSHClient')
    def test_execute_script_success(self, mock_ssh_class):
        """Test successful script execution."""
        mock_ssh = MagicMock()
        mock_ssh_class.return_value = mock_ssh

        mock_stdout = MagicMock()
        mock_stdout.read.return_value = b'Success'
        mock_stdout.channel.recv_exit_status.return_value = 0

        mock_stderr = MagicMock()
        mock_stderr.read.return_value = b''

        mock_ssh.exec_command.return_value = (MagicMock(), mock_stdout, mock_stderr)

        success, output, error = execute_script_via_ssh(
            server_ip='192.168.1.1',
            server_root_password='password',
            script_name='test-script'
        )

        self.assertTrue(success)
        self.assertEqual(output, 'Success')
        self.assertIsNone(error)

    @unittest.skipIf(not SSH_AVAILABLE, "paramiko not installed")
    @patch('app.paramiko.SSHClient')
    def test_execute_script_with_additional_params(self, mock_ssh_class):
        """Test script execution with additional parameters."""
        mock_ssh = MagicMock()
        mock_ssh_class.return_value = mock_ssh

        mock_stdout = MagicMock()
        mock_stdout.read.return_value = b'Done'
        mock_stdout.channel.recv_exit_status.return_value = 0

        mock_stderr = MagicMock()
        mock_stderr.read.return_value = b''

        mock_ssh.exec_command.return_value = (MagicMock(), mock_stdout, mock_stderr)

        success, output, error = execute_script_via_ssh(
            server_ip='192.168.1.1',
            server_root_password='password',
            script_name='test-script',
            additional='example.com'
        )

        self.assertTrue(success)
        # Verify the command includes the additional parameter
        mock_ssh.exec_command.assert_called_once()
        call_args = mock_ssh.exec_command.call_args[0][0]
        self.assertIn('example.com', call_args)

    @unittest.skipIf(not SSH_AVAILABLE, "paramiko not installed")
    @patch('app.paramiko.SSHClient')
    def test_execute_script_connection_timeout(self, mock_ssh_class):
        """Test handling of connection timeout."""
        mock_ssh = MagicMock()
        mock_ssh_class.return_value = mock_ssh
        mock_ssh.connect.side_effect = TimeoutError('Connection timed out')

        success, output, error = execute_script_via_ssh(
            server_ip='192.168.1.1',
            server_root_password='password',
            script_name='test-script'
        )

        self.assertFalse(success)
        self.assertEqual(output, '')
        self.assertIn('timed out', error)


class TestIndexEndpointWithInstall(unittest.TestCase):
    """Test that index endpoint includes install route."""

    def setUp(self):
        """Set up test client."""
        self.app = app
        self.app.config['TESTING'] = True
        self.client = self.app.test_client()

    def test_index_includes_install_endpoint(self):
        """Test that the root endpoint lists the /api/install endpoint."""
        response = self.client.get('/')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertIn('/api/install', data['endpoints'])

    def test_index_includes_status_endpoint(self):
        """Test that the root endpoint lists the /api/status/<task_id> endpoint."""
        response = self.client.get('/')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertIn('/api/status/<task_id>', data['endpoints'])


class TestTaskHelperFunctions(unittest.TestCase):
    """Test cases for task helper functions."""

    def setUp(self):
        """Ensure tasks directory exists."""
        os.makedirs(TASKS_DIR, exist_ok=True)
        self.test_task_id = 'test_task_123456789abcdef0'

    def tearDown(self):
        """Clean up test task files."""
        task_file = get_task_file_path(self.test_task_id)
        if os.path.exists(task_file):
            os.remove(task_file)

    def test_generate_task_id_consistency(self):
        """Test that generate_task_id produces consistent results."""
        task_id1 = generate_task_id('script', '192.168.1.1', 'password', 'extra')
        task_id2 = generate_task_id('script', '192.168.1.1', 'password', 'extra')
        self.assertEqual(task_id1, task_id2)

    def test_generate_task_id_uniqueness(self):
        """Test that different parameters produce different task IDs."""
        task_id1 = generate_task_id('script1', '192.168.1.1', 'password', 'extra')
        task_id2 = generate_task_id('script2', '192.168.1.1', 'password', 'extra')
        self.assertNotEqual(task_id1, task_id2)

    def test_generate_task_id_format(self):
        """Test that task ID is a valid MD5 hash format."""
        task_id = generate_task_id('script', '192.168.1.1', 'password', 'extra')
        self.assertRegex(task_id, r'^[a-f0-9]{32}$')

    def test_get_task_file_path(self):
        """Test that get_task_file_path returns correct path."""
        path = get_task_file_path('abc123')
        self.assertTrue(path.endswith('abc123.txt'))
        self.assertIn(TASKS_DIR, path)

    def test_write_and_read_task_status(self):
        """Test writing and reading task status."""
        write_task_status(self.test_task_id, TASK_STATUS_PROCESSING, 'Test content')
        status, content = read_task_status(self.test_task_id)
        self.assertEqual(status, TASK_STATUS_PROCESSING)
        self.assertEqual(content, 'Test content')

    def test_read_task_status_not_found(self):
        """Test reading non-existent task returns None."""
        status, content = read_task_status('non_existent_task')
        self.assertIsNone(status)
        self.assertIsNone(content)

    def test_delete_task_file(self):
        """Test deleting task file."""
        write_task_status(self.test_task_id, TASK_STATUS_COMPLETED, 'Done')
        task_file = get_task_file_path(self.test_task_id)
        self.assertTrue(os.path.exists(task_file))

        delete_task_file(self.test_task_id)
        self.assertFalse(os.path.exists(task_file))

    def test_delete_nonexistent_task_file(self):
        """Test deleting non-existent task file doesn't raise error."""
        # Should not raise any exception
        delete_task_file('non_existent_task')


class TestStatusEndpoint(unittest.TestCase):
    """Test cases for the /api/status/<task_id> endpoint."""

    def setUp(self):
        """Set up test client."""
        self.app = app
        self.app.config['TESTING'] = True
        self.client = self.app.test_client()
        os.makedirs(TASKS_DIR, exist_ok=True)
        self.test_task_id = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4'

    def tearDown(self):
        """Clean up test task files."""
        task_file = get_task_file_path(self.test_task_id)
        if os.path.exists(task_file):
            os.remove(task_file)

    def test_status_endpoint_invalid_task_id_format(self):
        """Test that /api/status returns 400 for invalid task_id format."""
        response = self.client.get('/api/status/invalid-task-id')
        self.assertEqual(response.status_code, 400)
        data = response.get_json()
        self.assertFalse(data['success'])
        self.assertIn('Invalid task_id format', data['error'])

    def test_status_endpoint_task_not_found(self):
        """Test that /api/status returns 404 for non-existent task."""
        response = self.client.get('/api/status/a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4')
        self.assertEqual(response.status_code, 404)
        data = response.get_json()
        self.assertFalse(data['success'])
        self.assertIn('Task not found', data['error'])

    def test_status_endpoint_processing_task(self):
        """Test that /api/status returns correct status for processing task."""
        write_task_status(self.test_task_id, TASK_STATUS_PROCESSING, 'Working...')
        response = self.client.get(f'/api/status/{self.test_task_id}')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertTrue(data['success'])
        self.assertEqual(data['status'], TASK_STATUS_PROCESSING)
        self.assertEqual(data['result'], 'Working...')

        # Task file should still exist for processing status
        self.assertTrue(os.path.exists(get_task_file_path(self.test_task_id)))

    def test_status_endpoint_completed_task_and_cleanup(self):
        """Test that /api/status returns correct status and cleans up completed task."""
        write_task_status(self.test_task_id, TASK_STATUS_COMPLETED, 'All done!')
        response = self.client.get(f'/api/status/{self.test_task_id}')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertTrue(data['success'])
        self.assertEqual(data['status'], TASK_STATUS_COMPLETED)
        self.assertEqual(data['result'], 'All done!')

        # Task file should be deleted after completed status is retrieved
        self.assertFalse(os.path.exists(get_task_file_path(self.test_task_id)))

    def test_status_endpoint_error_task_and_cleanup(self):
        """Test that /api/status returns correct status and cleans up error task."""
        write_task_status(self.test_task_id, TASK_STATUS_ERROR, 'Something went wrong')
        response = self.client.get(f'/api/status/{self.test_task_id}')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertTrue(data['success'])
        self.assertEqual(data['status'], TASK_STATUS_ERROR)
        self.assertEqual(data['result'], 'Something went wrong')

        # Task file should be deleted after error status is retrieved
        self.assertFalse(os.path.exists(get_task_file_path(self.test_task_id)))

    def test_status_endpoint_second_request_returns_not_found(self):
        """Test that second request for completed task returns not found."""
        write_task_status(self.test_task_id, TASK_STATUS_COMPLETED, 'Done')

        # First request should succeed
        response1 = self.client.get(f'/api/status/{self.test_task_id}')
        self.assertEqual(response1.status_code, 200)

        # Second request should return 404
        response2 = self.client.get(f'/api/status/{self.test_task_id}')
        self.assertEqual(response2.status_code, 404)
        data = response2.get_json()
        self.assertIn('Task not found', data['error'])


class TestStripAnsiCodes(unittest.TestCase):
    """Test cases for the strip_ansi_codes function."""

    def test_strip_basic_colors(self):
        """Test stripping basic color codes."""
        self.assertEqual(strip_ansi_codes("\033[31mRed text\033[0m"), "Red text")
        self.assertEqual(strip_ansi_codes("\033[32mGreen text\033[0m"), "Green text")
        self.assertEqual(strip_ansi_codes("\033[1;34mBold blue\033[0m"), "Bold blue")

    def test_strip_extended_colors(self):
        """Test stripping extended color codes."""
        self.assertEqual(strip_ansi_codes("\033[38;5;196mExtended color\033[0m"), "Extended color")
        self.assertEqual(strip_ansi_codes("\033[48;2;255;0;0mTrue color bg\033[0m"), "True color bg")

    def test_strip_multiple_colors(self):
        """Test stripping multiple color codes in one line."""
        self.assertEqual(
            strip_ansi_codes("\033[31mRed\033[0m and \033[32mGreen\033[0m"),
            "Red and Green"
        )

    def test_strip_common_script_output(self):
        """Test stripping colors from common script output patterns."""
        self.assertEqual(
            strip_ansi_codes("[ \033[32mOK\033[0m ] Service started"),
            "[ OK ] Service started"
        )
        self.assertEqual(
            strip_ansi_codes("[\033[31mFAIL\033[0m] Service failed"),
            "[FAIL] Service failed"
        )

    def test_strip_cursor_movement_codes(self):
        """Test stripping cursor movement codes."""
        self.assertEqual(strip_ansi_codes("\033[2J\033[H"), "")  # Clear screen
        self.assertEqual(strip_ansi_codes("Line 1\033[A"), "Line 1")  # Cursor up

    def test_strip_erase_line_codes(self):
        """Test stripping erase line codes."""
        self.assertEqual(strip_ansi_codes("Progress: \033[K50%"), "Progress: 50%")

    def test_strip_only_escape_sequences(self):
        """Test that lines with only escape sequences become empty."""
        self.assertEqual(strip_ansi_codes("\033[0m\033[K"), "")

    def test_preserve_empty_string(self):
        """Test that empty strings are handled correctly."""
        self.assertEqual(strip_ansi_codes(""), "")

    def test_preserve_none(self):
        """Test that None is handled correctly."""
        self.assertIsNone(strip_ansi_codes(None))

    def test_preserve_plain_text(self):
        """Test that plain text without escape codes is preserved."""
        self.assertEqual(
            strip_ansi_codes("Plain text without escape codes"),
            "Plain text without escape codes"
        )

    def test_preserve_newlines(self):
        """Test that newlines are preserved."""
        self.assertEqual(
            strip_ansi_codes("Line 1\nLine 2\n\033[32mLine 3\033[0m\n"),
            "Line 1\nLine 2\nLine 3\n"
        )

    def test_strip_hex_escape_format(self):
        """Test stripping hex escape character format."""
        self.assertEqual(strip_ansi_codes("\x1b[31mRed\x1b[0m"), "Red")

    def test_strip_text_formatting(self):
        """Test stripping bold, italic, underline codes."""
        self.assertEqual(strip_ansi_codes("\033[1mBold\033[0m"), "Bold")
        self.assertEqual(strip_ansi_codes("\033[3mItalic\033[0m"), "Italic")
        self.assertEqual(strip_ansi_codes("\033[4mUnderline\033[0m"), "Underline")

    def test_strip_combined_attributes(self):
        """Test stripping combined formatting attributes."""
        self.assertEqual(
            strip_ansi_codes("\033[1;4;31mBold underline red\033[0m"),
            "Bold underline red"
        )

    def test_strip_null_characters(self):
        """Test stripping NULL characters (\\x00)."""
        self.assertEqual(strip_ansi_codes("Hello\x00World"), "HelloWorld")
        self.assertEqual(strip_ansi_codes("\x00\x00\x00Text\x00\x00"), "Text")
        # Many NULL characters as seen in real terminal output
        self.assertEqual(
            strip_ansi_codes("Before\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00After"),
            "BeforeAfter"
        )

    def test_strip_other_control_characters(self):
        """Test stripping other non-printable control characters."""
        # Bell character (\\x07) - note: BEL is stripped as part of control chars
        self.assertEqual(strip_ansi_codes("Text\x07here"), "Texthere")
        # Backspace (\\x08)
        self.assertEqual(strip_ansi_codes("Text\x08here"), "Texthere")
        # Vertical tab (\\x0b)
        self.assertEqual(strip_ansi_codes("Text\x0bhere"), "Texthere")
        # Form feed (\\x0c)
        self.assertEqual(strip_ansi_codes("Text\x0chere"), "Texthere")
        # Delete (\\x7f)
        self.assertEqual(strip_ansi_codes("Text\x7fhere"), "Texthere")

    def test_preserve_tabs_and_newlines(self):
        """Test that tabs (\\x09) and newlines (\\x0a) are preserved."""
        self.assertEqual(strip_ansi_codes("Line1\nLine2"), "Line1\nLine2")
        self.assertEqual(strip_ansi_codes("Col1\tCol2"), "Col1\tCol2")
        self.assertEqual(strip_ansi_codes("Line1\r\nLine2"), "Line1\r\nLine2")

    def test_strip_mixed_ansi_and_control_chars(self):
        """Test stripping mixed ANSI codes and control characters."""
        input_text = "\x1b[32mGreen\x1b[0m\x00\x00\x00Text\x1b[H\x1b[J"
        expected = "GreenText"
        self.assertEqual(strip_ansi_codes(input_text), expected)

    def test_strip_complex_terminal_output(self):
        """Test stripping complex terminal output similar to real-world data."""
        # Simulating output like in the issue
        input_text = (
            "Starting installation...\n"
            "\x1b[0;36m╔═══════════════════════════╗\x1b[0m\n"
            "\x1b[0;36m║\x1b[0m  \x1b[1;37mDomain Config\x1b[0m\n"
            "\x1b[H\x1b[J"  # Screen clear
            "\x00\x00\x00\x00\x00\x00\x00\x00"  # NULL characters
            "\x1b[0;32m✔\x1b[0m Done\n"
        )
        expected = (
            "Starting installation...\n"
            "╔═══════════════════════════╗\n"
            "║  Domain Config\n"
            "✔ Done\n"
        )
        self.assertEqual(strip_ansi_codes(input_text), expected)


class TestAnsiStrippingIntegration(unittest.TestCase):
    """Test ANSI code stripping integration with task functions."""

    def setUp(self):
        """Set up test environment."""
        os.makedirs(TASKS_DIR, exist_ok=True)
        # Use a valid MD5 hash format (32 hex characters) for task_id
        # Using a different task_id than TestStatusEndpoint to avoid conflicts
        self.test_task_id = 'b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5'

    def tearDown(self):
        """Clean up test task files."""
        task_file = get_task_file_path(self.test_task_id)
        if os.path.exists(task_file):
            os.remove(task_file)

    def test_write_task_status_strips_ansi(self):
        """Test that write_task_status strips ANSI codes from content."""
        colored_content = "[\033[32mOK\033[0m] Installation \033[1;34mcomplete\033[0m"
        expected_content = "[OK] Installation complete"

        write_task_status(self.test_task_id, TASK_STATUS_COMPLETED, colored_content)
        status, content = read_task_status(self.test_task_id)

        self.assertEqual(status, TASK_STATUS_COMPLETED)
        self.assertEqual(content, expected_content)

    def test_append_task_content_strips_ansi(self):
        """Test that append_task_content strips ANSI codes from content."""
        write_task_status(self.test_task_id, TASK_STATUS_PROCESSING, "Starting...\n")

        colored_line = "\033[33mProcessing...\033[0m\n"
        append_task_content(self.test_task_id, colored_line)

        status, content = read_task_status(self.test_task_id)
        self.assertIn("Starting...", content)
        self.assertIn("Processing...", content)
        self.assertNotIn("\033", content)  # No escape characters

    def test_status_endpoint_returns_clean_content(self):
        """Test that /api/status endpoint returns content without ANSI codes."""
        # Write content with ANSI codes (simulating old data that might still have codes)
        task_file = get_task_file_path(self.test_task_id)
        with open(task_file, 'w', encoding='utf-8') as f:
            f.write(f"STATUS:{TASK_STATUS_COMPLETED}\n")
            f.write("[\033[32mOK\033[0m] Done")

        app.config['TESTING'] = True
        client = app.test_client()

        response = client.get(f'/api/status/{self.test_task_id}')
        data = response.get_json()

        self.assertTrue(data['success'])
        self.assertEqual(data['result'], "[OK] Done")
        self.assertNotIn("\033", data['result'])

    def test_write_task_status_strips_null_chars(self):
        """Test that write_task_status strips NULL characters from content."""
        content_with_nulls = "Text\x00\x00\x00before\x00after"
        expected_content = "Textbeforeafter"

        write_task_status(self.test_task_id, TASK_STATUS_COMPLETED, content_with_nulls)
        status, content = read_task_status(self.test_task_id)

        self.assertEqual(status, TASK_STATUS_COMPLETED)
        self.assertEqual(content, expected_content)
        self.assertNotIn("\x00", content)

    def test_append_task_content_strips_null_chars(self):
        """Test that append_task_content strips NULL characters."""
        write_task_status(self.test_task_id, TASK_STATUS_PROCESSING, "Start\n")

        content_with_nulls = "\x00\x00\x00Processing\x00\x00\n"
        append_task_content(self.test_task_id, content_with_nulls)

        status, content = read_task_status(self.test_task_id)
        self.assertIn("Start", content)
        self.assertIn("Processing", content)
        self.assertNotIn("\x00", content)

    def test_status_endpoint_strips_null_chars_from_old_data(self):
        """Test that /api/status endpoint strips NULL chars from existing files."""
        # Write content with NULL characters (simulating old data)
        task_file = get_task_file_path(self.test_task_id)
        with open(task_file, 'w', encoding='utf-8') as f:
            f.write(f"STATUS:{TASK_STATUS_COMPLETED}\n")
            f.write("Text\x00\x00\x00with\x00nulls")

        app.config['TESTING'] = True
        client = app.test_client()

        response = client.get(f'/api/status/{self.test_task_id}')
        data = response.get_json()

        self.assertTrue(data['success'])
        self.assertEqual(data['result'], "Textwithnulls")
        self.assertNotIn("\x00", data['result'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
