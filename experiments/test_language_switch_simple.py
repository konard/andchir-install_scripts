#!/usr/bin/env python3
"""
Simple test script to verify the language switching code without GUI.
"""

import sys
import os

# Add parent directory to path to import the main module
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'gui'))

from main import TRANSLATIONS, DEFAULT_LANG, load_scripts

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

    # Check English translation
    assert TRANSLATIONS['en']['language_label'] == 'Language:', f"English language_label should be 'Language:', got '{TRANSLATIONS['en']['language_label']}'"
    print("✓ English language_label is correct")

    # Check Russian translation
    assert TRANSLATIONS['ru']['language_label'] == 'Язык:', f"Russian language_label should be 'Язык:', got '{TRANSLATIONS['ru']['language_label']}'"
    print("✓ Russian language_label is correct")

def test_load_scripts():
    """Test that scripts can be loaded for both languages."""
    # Change to the parent directory to find data files
    original_dir = os.getcwd()
    os.chdir(os.path.join(os.path.dirname(__file__), '..'))

    try:
        en_scripts = load_scripts('en')
        ru_scripts = load_scripts('ru')

        assert len(en_scripts) > 0, "English scripts should be loaded"
        assert len(ru_scripts) > 0, "Russian scripts should be loaded"
        print(f"✓ Loaded {len(en_scripts)} English scripts")
        print(f"✓ Loaded {len(ru_scripts)} Russian scripts")

    finally:
        os.chdir(original_dir)

if __name__ == '__main__':
    print("Testing language switching functionality (simple tests)...\n")

    try:
        test_default_language()
        test_translations_exist()
        test_load_scripts()

        print("\n✓ All tests passed!")
        sys.exit(0)

    except AssertionError as e:
        print(f"\n✗ Test failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
