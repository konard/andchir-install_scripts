#!/usr/bin/env python3
"""
Test script to verify data file loading works correctly.

This tests both the regular Python execution and simulates
the PyInstaller frozen environment behavior.
"""

import sys
import os

# Add the gui directory to path so we can import from main
gui_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'gui')
sys.path.insert(0, gui_dir)

# Import the functions we want to test
from main import get_base_path, get_data_file_path, load_scripts

def test_regular_execution():
    """Test that data files are found in regular Python execution."""
    print("=" * 60)
    print("Testing regular Python execution mode")
    print("=" * 60)

    # Check if we're frozen (should be False in this test)
    is_frozen = getattr(sys, 'frozen', False)
    print(f"sys.frozen: {is_frozen}")

    # Test get_base_path
    base_path = get_base_path()
    print(f"Base path: {base_path}")
    print(f"Base path exists: {os.path.exists(base_path)}")

    # Test get_data_file_path
    print("\nData file paths:")
    for lang in ['ru', 'en', 'invalid']:
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
            print(f"       Last:  {scripts[-1].get('name', 'N/A')}")

    return True


def test_simulated_frozen():
    """Simulate PyInstaller frozen environment to test path resolution."""
    print("\n" + "=" * 60)
    print("Testing simulated PyInstaller frozen mode")
    print("=" * 60)

    # Get the project root (where data files are)
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    # Simulate frozen mode by setting sys.frozen and sys._MEIPASS
    sys.frozen = True
    sys._MEIPASS = project_root

    try:
        # Test get_base_path
        base_path = get_base_path()
        print(f"Base path (simulated _MEIPASS): {base_path}")
        print(f"Expected: {project_root}")
        print(f"Match: {base_path == project_root}")

        # Test get_data_file_path
        print("\nData file paths (simulated frozen):")
        for lang in ['ru', 'en']:
            data_file = get_data_file_path(lang)
            exists = os.path.exists(data_file) if data_file else False
            print(f"  {lang}: {data_file}")
            print(f"       exists: {exists}")

        # Test load_scripts
        print("\nScript loading (simulated frozen):")
        for lang in ['ru', 'en']:
            scripts = load_scripts(lang)
            print(f"  {lang}: {len(scripts)} scripts loaded")

        return True
    finally:
        # Clean up: remove simulated frozen attributes
        del sys.frozen
        del sys._MEIPASS


def main():
    """Run all tests."""
    print("Data Loading Test Suite")
    print("Testing fix for GitHub issue: script list not showing on Windows")
    print()

    success = True

    try:
        success &= test_regular_execution()
    except Exception as e:
        print(f"ERROR in regular execution test: {e}")
        success = False

    try:
        success &= test_simulated_frozen()
    except Exception as e:
        print(f"ERROR in simulated frozen test: {e}")
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
