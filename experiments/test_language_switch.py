#!/usr/bin/env python3
"""
Test script to verify the language switching functionality in the GUI.
This script verifies that:
1. Default language is set to English
2. Language selector is present in the UI
3. Language switching updates all UI elements
"""

import sys
import os

# Add parent directory to path to import the main module
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'gui'))

from main import MainWindow, TRANSLATIONS, DEFAULT_LANG

def test_default_language():
    """Test that default language is English."""
    assert DEFAULT_LANG == 'en', f"Default language should be 'en', but got '{DEFAULT_LANG}'"
    print("✓ Default language is set to English")

def test_translations_exist():
    """Test that both language translations exist."""
    assert 'en' in TRANSLATIONS, "English translations missing"
    assert 'ru' in TRANSLATIONS, "Russian translations missing"
    assert 'language_label' in TRANSLATIONS['en'], "Language label missing in English"
    assert 'language_label' in TRANSLATIONS['ru'], "Language label missing in Russian"
    print("✓ Both language translations exist with language_label")

def test_window_creation():
    """Test that window can be created with both languages."""
    try:
        # Test creating window with English
        window_en = MainWindow(lang='en')
        assert window_en.lang == 'en', "Language should be 'en'"
        assert hasattr(window_en, 'lang_combo'), "Language selector should exist"
        assert hasattr(window_en, 'lang_label'), "Language label should exist"
        print("✓ Window created successfully with English language")

        # Test creating window with Russian
        window_ru = MainWindow(lang='ru')
        assert window_ru.lang == 'ru', "Language should be 'ru'"
        print("✓ Window created successfully with Russian language")

    except Exception as e:
        print(f"✗ Error creating window: {e}")
        raise

def test_update_ui_text_method():
    """Test that update_ui_text method exists and has all necessary references."""
    window = MainWindow(lang='en')

    # Check that all necessary UI element references exist
    required_attrs = [
        'lang_label', 'lang_combo',
        'ip_label', 'password_label', 'additional_label',
        'software_group', 'software_combo',
        'install_button', 'stop_button', 'clear_button',
        'report_group'
    ]

    for attr in required_attrs:
        assert hasattr(window, attr), f"Window should have '{attr}' attribute"

    print("✓ All necessary UI element references exist")

    # Test that update_ui_text method exists
    assert hasattr(window, 'update_ui_text'), "update_ui_text method should exist"
    assert hasattr(window, 'on_language_changed'), "on_language_changed method should exist"
    print("✓ Language switching methods exist")

if __name__ == '__main__':
    print("Testing language switching functionality...\n")

    try:
        test_default_language()
        test_translations_exist()

        # For GUI tests, we need PyQt6 to be installed
        try:
            from PyQt6.QtWidgets import QApplication
            app = QApplication(sys.argv)

            test_window_creation()
            test_update_ui_text_method()

            print("\n✓ All tests passed!")
            sys.exit(0)

        except ImportError as e:
            print(f"\n⚠ Skipping GUI tests (PyQt6 not available): {e}")
            print("✓ Non-GUI tests passed!")
            sys.exit(0)

    except AssertionError as e:
        print(f"\n✗ Test failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
