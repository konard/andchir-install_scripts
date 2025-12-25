#!/usr/bin/env python3
"""
Unit tests for cleanup_old_task_files function.

These tests verify that the function correctly:
1. Deletes files older than the specified age
2. Keeps files newer than the specified age
3. Only processes .txt files in the tasks directory
4. Handles edge cases like missing directory
"""

import os
import sys
import time
import tempfile
import shutil
import unittest

# Add the api directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'api'))


class TestCleanupOldTaskFiles(unittest.TestCase):
    """Tests for the cleanup_old_task_files function."""

    def setUp(self):
        """Set up a temporary tasks directory for testing."""
        self.temp_dir = tempfile.mkdtemp()
        self.original_tasks_dir = None

    def tearDown(self):
        """Clean up the temporary directory."""
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def _create_test_file(self, filename, age_seconds):
        """Create a test file with a specific age.

        Args:
            filename: Name of the file to create
            age_seconds: How old the file should be (in seconds)
        """
        file_path = os.path.join(self.temp_dir, filename)
        with open(file_path, 'w') as f:
            f.write('STATUS:completed\nTest content')

        # Set the modification time to simulate file age
        current_time = time.time()
        old_time = current_time - age_seconds
        os.utime(file_path, (old_time, old_time))

        return file_path

    def test_delete_old_files(self):
        """Test that old files are deleted."""
        # Import here to get fresh module with our patched TASKS_DIR
        import importlib
        import api.app as app_module

        # Store original and set new TASKS_DIR
        original_tasks_dir = app_module.TASKS_DIR
        app_module.TASKS_DIR = self.temp_dir

        try:
            # Create an old file (2 hours old) and a new file (5 minutes old)
            self._create_test_file('old_task.txt', 7200)  # 2 hours old
            self._create_test_file('new_task.txt', 300)   # 5 minutes old

            # Verify both files exist
            self.assertTrue(os.path.exists(os.path.join(self.temp_dir, 'old_task.txt')))
            self.assertTrue(os.path.exists(os.path.join(self.temp_dir, 'new_task.txt')))

            # Run cleanup with 30 minute threshold
            deleted_count = app_module.cleanup_old_task_files(max_age_seconds=1800)

            # Old file should be deleted, new file should remain
            self.assertEqual(deleted_count, 1)
            self.assertFalse(os.path.exists(os.path.join(self.temp_dir, 'old_task.txt')))
            self.assertTrue(os.path.exists(os.path.join(self.temp_dir, 'new_task.txt')))
        finally:
            # Restore original TASKS_DIR
            app_module.TASKS_DIR = original_tasks_dir

    def test_keep_new_files(self):
        """Test that new files are kept."""
        import api.app as app_module

        original_tasks_dir = app_module.TASKS_DIR
        app_module.TASKS_DIR = self.temp_dir

        try:
            # Create files that are all newer than the threshold
            self._create_test_file('task1.txt', 60)   # 1 minute old
            self._create_test_file('task2.txt', 300)  # 5 minutes old
            self._create_test_file('task3.txt', 900)  # 15 minutes old

            # Run cleanup with 30 minute threshold
            deleted_count = app_module.cleanup_old_task_files(max_age_seconds=1800)

            # No files should be deleted
            self.assertEqual(deleted_count, 0)
            self.assertTrue(os.path.exists(os.path.join(self.temp_dir, 'task1.txt')))
            self.assertTrue(os.path.exists(os.path.join(self.temp_dir, 'task2.txt')))
            self.assertTrue(os.path.exists(os.path.join(self.temp_dir, 'task3.txt')))
        finally:
            app_module.TASKS_DIR = original_tasks_dir

    def test_only_txt_files(self):
        """Test that only .txt files are processed."""
        import api.app as app_module

        original_tasks_dir = app_module.TASKS_DIR
        app_module.TASKS_DIR = self.temp_dir

        try:
            # Create old files with different extensions
            self._create_test_file('task.txt', 7200)
            self._create_test_file('task.log', 7200)
            self._create_test_file('task.json', 7200)

            # Run cleanup
            deleted_count = app_module.cleanup_old_task_files(max_age_seconds=1800)

            # Only .txt file should be deleted
            self.assertEqual(deleted_count, 1)
            self.assertFalse(os.path.exists(os.path.join(self.temp_dir, 'task.txt')))
            self.assertTrue(os.path.exists(os.path.join(self.temp_dir, 'task.log')))
            self.assertTrue(os.path.exists(os.path.join(self.temp_dir, 'task.json')))
        finally:
            app_module.TASKS_DIR = original_tasks_dir

    def test_empty_directory(self):
        """Test cleanup on an empty directory."""
        import api.app as app_module

        original_tasks_dir = app_module.TASKS_DIR
        app_module.TASKS_DIR = self.temp_dir

        try:
            # Directory is empty
            deleted_count = app_module.cleanup_old_task_files(max_age_seconds=1800)

            self.assertEqual(deleted_count, 0)
        finally:
            app_module.TASKS_DIR = original_tasks_dir

    def test_nonexistent_directory(self):
        """Test cleanup when directory doesn't exist."""
        import api.app as app_module

        original_tasks_dir = app_module.TASKS_DIR
        nonexistent_dir = '/tmp/nonexistent_tasks_dir_12345'
        app_module.TASKS_DIR = nonexistent_dir

        try:
            # Should handle gracefully
            deleted_count = app_module.cleanup_old_task_files(max_age_seconds=1800)
            self.assertEqual(deleted_count, 0)
        finally:
            app_module.TASKS_DIR = original_tasks_dir

    def test_multiple_old_files(self):
        """Test cleanup of multiple old files."""
        import api.app as app_module

        original_tasks_dir = app_module.TASKS_DIR
        app_module.TASKS_DIR = self.temp_dir

        try:
            # Create multiple old files
            for i in range(5):
                self._create_test_file(f'old_task_{i}.txt', 7200)

            # Create some new files
            for i in range(3):
                self._create_test_file(f'new_task_{i}.txt', 300)

            # Run cleanup
            deleted_count = app_module.cleanup_old_task_files(max_age_seconds=1800)

            # 5 old files should be deleted, 3 new files should remain
            self.assertEqual(deleted_count, 5)

            remaining_files = os.listdir(self.temp_dir)
            self.assertEqual(len(remaining_files), 3)
            for f in remaining_files:
                self.assertTrue(f.startswith('new_task_'))
        finally:
            app_module.TASKS_DIR = original_tasks_dir

    def test_custom_max_age(self):
        """Test cleanup with custom max age."""
        import api.app as app_module

        original_tasks_dir = app_module.TASKS_DIR
        app_module.TASKS_DIR = self.temp_dir

        try:
            # Create files with different ages
            self._create_test_file('very_old.txt', 3600)  # 1 hour
            self._create_test_file('medium_old.txt', 600)  # 10 minutes
            self._create_test_file('new.txt', 60)  # 1 minute

            # Cleanup with 5-minute threshold
            deleted_count = app_module.cleanup_old_task_files(max_age_seconds=300)

            # Files older than 5 minutes should be deleted
            self.assertEqual(deleted_count, 2)
            self.assertFalse(os.path.exists(os.path.join(self.temp_dir, 'very_old.txt')))
            self.assertFalse(os.path.exists(os.path.join(self.temp_dir, 'medium_old.txt')))
            self.assertTrue(os.path.exists(os.path.join(self.temp_dir, 'new.txt')))
        finally:
            app_module.TASKS_DIR = original_tasks_dir


if __name__ == '__main__':
    unittest.main(verbosity=2)
