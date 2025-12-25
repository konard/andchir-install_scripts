#!/usr/bin/env python3
"""
Test script for the /api/scripts_list endpoint.

This script tests:
1. Default language (ru) loads data_ru.json
2. Explicit lang=ru loads data_ru.json
3. Explicit lang=en loads data_en.json
4. Unknown language falls back to data_ru.json
"""

import sys
import os

# Add the api directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'api'))

from app import app, get_data_file_path, DATA_DIR


def test_get_data_file_path():
    """Test the get_data_file_path function."""
    print("Testing get_data_file_path function...")

    # Test default language (ru)
    ru_path = get_data_file_path('ru')
    expected_ru = os.path.join(DATA_DIR, 'data_ru.json')
    assert ru_path == expected_ru, f"Expected {expected_ru}, got {ru_path}"
    print(f"  lang=ru: {ru_path} - OK")

    # Test English language (en)
    en_path = get_data_file_path('en')
    expected_en = os.path.join(DATA_DIR, 'data_en.json')
    assert en_path == expected_en, f"Expected {expected_en}, got {en_path}"
    print(f"  lang=en: {en_path} - OK")

    # Test unknown language (should fall back to ru)
    unknown_path = get_data_file_path('unknown')
    assert unknown_path == expected_ru, f"Expected fallback to {expected_ru}, got {unknown_path}"
    print(f"  lang=unknown: {unknown_path} (fallback) - OK")

    print("get_data_file_path tests passed!\n")


def test_scripts_list_endpoint():
    """Test the /api/scripts_list endpoint."""
    print("Testing /api/scripts_list endpoint...")

    with app.test_client() as client:
        # Test 1: Default language (no query parameter)
        print("  Test 1: Default language (no param)")
        response = client.get('/api/scripts_list')
        assert response.status_code == 200, f"Expected 200, got {response.status_code}"
        data = response.get_json()
        assert data['success'] is True
        assert data['count'] == 3
        # Check that it's Russian (check for Russian word in description)
        assert 'API для' in data['scripts'][0]['description'] or 'Видео' in data['scripts'][2]['description']
        print(f"    Response: success={data['success']}, count={data['count']}")
        print("    Contains Russian text - OK")

        # Test 2: Explicit lang=ru
        print("  Test 2: Explicit lang=ru")
        response = client.get('/api/scripts_list?lang=ru')
        assert response.status_code == 200
        data = response.get_json()
        assert data['success'] is True
        assert data['count'] == 3
        print(f"    Response: success={data['success']}, count={data['count']} - OK")

        # Test 3: Explicit lang=en
        print("  Test 3: Explicit lang=en")
        response = client.get('/api/scripts_list?lang=en')
        assert response.status_code == 200
        data = response.get_json()
        assert data['success'] is True
        assert data['count'] == 3
        # Check that it's English
        assert 'API for installing' in data['scripts'][0]['description'] or 'Video chat' in data['scripts'][2]['description']
        print(f"    Response: success={data['success']}, count={data['count']}")
        print("    Contains English text - OK")

        # Test 4: Unknown language (should fall back to ru)
        print("  Test 4: Unknown language (lang=de), should fallback to ru")
        response = client.get('/api/scripts_list?lang=de')
        assert response.status_code == 200
        data = response.get_json()
        assert data['success'] is True
        assert data['count'] == 3
        # Should fall back to Russian
        assert 'API для' in data['scripts'][0]['description'] or 'Видео' in data['scripts'][2]['description']
        print(f"    Response: success={data['success']}, count={data['count']}")
        print("    Fallback to Russian - OK")

    print("\n/api/scripts_list endpoint tests passed!")


if __name__ == '__main__':
    print("=" * 60)
    print("Running tests for /api/scripts_list implementation")
    print("=" * 60 + "\n")

    test_get_data_file_path()
    test_scripts_list_endpoint()

    print("\n" + "=" * 60)
    print("All tests passed!")
    print("=" * 60)
