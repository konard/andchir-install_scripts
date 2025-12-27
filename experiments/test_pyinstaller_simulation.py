#!/usr/bin/env python3
"""
Test script that simulates PyInstaller behavior more accurately.

This script tests what happens when:
1. The application is running as a frozen executable
2. Data files need to be found in the bundle

The key insight is that PyInstaller onefile mode extracts files to a temp directory,
and we need to correctly locate those files.

Related to GitHub issue: https://github.com/andchir/install_scripts/issues/108
"""

import sys
import os
import tempfile
import shutil
import json
import logging

# Add the gui directory to path so we can import from main
gui_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'gui')
sys.path.insert(0, gui_dir)

from main import get_base_path, get_data_file_path, load_scripts, setup_logging

def test_pyinstaller_onefile_simulation():
    """
    Simulate PyInstaller onefile mode more accurately.

    In onefile mode, PyInstaller:
    1. Extracts bundled files to a temp directory
    2. Sets sys._MEIPASS to that temp directory
    3. The application accesses files from sys._MEIPASS
    """
    print("=" * 60)
    print("PyInstaller ONEFILE Mode Simulation")
    print("=" * 60)

    # Create a temporary directory to simulate _MEIPASS
    temp_dir = tempfile.mkdtemp(prefix='_MEI')
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    print(f"Simulated _MEIPASS (temp dir): {temp_dir}")
    print(f"Project root: {project_root}")

    # Copy data files to temp directory (simulating PyInstaller bundle extraction)
    for lang in ['ru', 'en']:
        src = os.path.join(project_root, f'data_{lang}.json')
        dst = os.path.join(temp_dir, f'data_{lang}.json')
        if os.path.exists(src):
            shutil.copy2(src, dst)
            print(f"Copied: {src} -> {dst}")
        else:
            print(f"WARNING: Source file not found: {src}")

    # Simulate frozen mode
    sys.frozen = True
    sys._MEIPASS = temp_dir

    try:
        print("\n--- Testing with simulated frozen mode ---")

        # Test get_base_path
        base_path = get_base_path()
        print(f"get_base_path() returned: {base_path}")
        print(f"Expected: {temp_dir}")
        print(f"Match: {base_path == temp_dir}")

        # Test get_data_file_path
        print("\nData file paths:")
        for lang in ['ru', 'en']:
            data_file = get_data_file_path(lang)
            exists = os.path.exists(data_file) if data_file else False
            print(f"  {lang}: {data_file}")
            print(f"       exists: {exists}")

        # Test load_scripts
        print("\nScript loading:")
        for lang in ['ru', 'en']:
            scripts = load_scripts(lang)
            print(f"  {lang}: {len(scripts)} scripts loaded")
            if scripts:
                print(f"       First: {scripts[0].get('name', 'N/A')}")

        scripts_ru = load_scripts('ru')
        scripts_en = load_scripts('en')
        success = len(scripts_ru) > 0 and len(scripts_en) > 0

        return success

    finally:
        # Clean up
        del sys.frozen
        del sys._MEIPASS
        shutil.rmtree(temp_dir, ignore_errors=True)
        print(f"\nCleaned up temp directory: {temp_dir}")


def test_potential_issues():
    """Test potential issues that could cause scripts to not load."""
    print("\n" + "=" * 60)
    print("Potential Issue Analysis")
    print("=" * 60)

    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    # Issue 1: Check for BOM or encoding issues in JSON files
    print("\n1. Checking JSON file encoding...")
    for lang in ['ru', 'en']:
        json_path = os.path.join(project_root, f'data_{lang}.json')
        if os.path.exists(json_path):
            with open(json_path, 'rb') as f:
                first_bytes = f.read(10)
                has_bom = first_bytes.startswith(b'\xef\xbb\xbf')
                print(f"   {lang}: First bytes: {first_bytes[:5]}, Has BOM: {has_bom}")

            # Test loading with different approaches
            try:
                with open(json_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    print(f"   {lang}: Loaded successfully with utf-8 encoding ({len(data)} items)")
            except Exception as e:
                print(f"   {lang}: Error loading: {e}")

    # Issue 2: Check if any silent exceptions are being raised
    print("\n2. Testing load_scripts with verbose error handling...")

    def verbose_load_scripts(lang):
        """Same as load_scripts but with verbose error reporting."""
        from main import get_data_file_path

        data_file = get_data_file_path(lang)
        print(f"   get_data_file_path('{lang}') = {data_file}")

        if not data_file:
            print(f"   WARNING: data_file is empty/None")
            return []

        if not os.path.exists(data_file):
            print(f"   WARNING: data_file does not exist: {data_file}")
            return []

        try:
            with open(data_file, 'r', encoding='utf-8') as f:
                content = f.read()
                print(f"   File content length: {len(content)} bytes")
                data = json.loads(content)
                print(f"   Parsed JSON: {type(data)}, length: {len(data) if isinstance(data, list) else 'N/A'}")
                return data
        except json.JSONDecodeError as e:
            print(f"   JSON ERROR: {e}")
            return []
        except IOError as e:
            print(f"   IO ERROR: {e}")
            return []

    for lang in ['ru', 'en']:
        print(f"\n   Testing {lang}:")
        verbose_load_scripts(lang)


def test_debug_logging():
    """Test that debug logging works correctly."""
    print("\n" + "=" * 60)
    print("Debug Logging Test")
    print("=" * 60)

    # Enable debug logging
    os.environ['INSTALL_SCRIPTS_DEBUG'] = '1'
    setup_logging(debug=True)

    # Load scripts - should produce debug output
    scripts = load_scripts('en')
    print(f"\nLoaded {len(scripts)} scripts with debug logging enabled")

    # Clean up
    del os.environ['INSTALL_SCRIPTS_DEBUG']

    return len(scripts) > 0


def main():
    """Run all tests."""
    print("PyInstaller Simulation Test Suite")
    print("Testing script loading behavior")
    print("Related to: https://github.com/andchir/install_scripts/issues/108")
    print()

    success = True

    try:
        success &= test_pyinstaller_onefile_simulation()
    except Exception as e:
        print(f"ERROR in onefile simulation: {e}")
        import traceback
        traceback.print_exc()
        success = False

    try:
        test_potential_issues()
    except Exception as e:
        print(f"ERROR in potential issues test: {e}")
        import traceback
        traceback.print_exc()

    try:
        success &= test_debug_logging()
    except Exception as e:
        print(f"ERROR in debug logging test: {e}")
        import traceback
        traceback.print_exc()
        success = False

    print("\n" + "=" * 60)
    if success:
        print("All tests passed!")
    else:
        print("Some tests failed!")
    print("=" * 60)

    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
