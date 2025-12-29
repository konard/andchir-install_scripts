#!/usr/bin/env python3
"""
Test script for the escape_shell_args function.

This verifies that the additional parameter parsing correctly splits
space-separated values into multiple arguments.
"""

import sys
import os


# Define the function inline (same as in api/app.py and gui/main.py)
def escape_shell_args(additional: str) -> str:
    """
    Escape and format additional parameters for shell execution.

    If the additional parameter contains spaces, it is split into multiple
    arguments. Each argument is properly escaped and quoted with single quotes.

    Args:
        additional: The additional parameter string (may contain spaces)

    Returns:
        A properly escaped string of shell arguments
    """
    if not additional:
        return ''

    # Split by whitespace to get individual arguments
    args = additional.split()

    # Escape each argument: replace single quotes with '\''
    escaped_args = []
    for arg in args:
        escaped_arg = arg.replace("'", "'\"'\"'")
        escaped_args.append(f"'{escaped_arg}'")

    return ' '.join(escaped_args)


def test_escape_shell_args():
    """Test the escape_shell_args function."""
    print("\n=== Testing escape_shell_args ===\n")

    test_cases = [
        # (input, expected output, description)
        ("", "", "Empty string"),
        ("domain.com", "'domain.com'", "Single argument"),
        ("arg1 arg2", "'arg1' 'arg2'", "Two arguments separated by space"),
        ("arg1 arg2 arg3", "'arg1' 'arg2' 'arg3'", "Three arguments"),
        ("example.com password123", "'example.com' 'password123'", "Domain and password"),
        ("  spaced  args  ", "'spaced' 'args'", "Multiple spaces should be handled"),
        ("it's-a-test", "'it'\"'\"'s-a-test'", "Single quote in middle"),
        ("arg'with'quotes another", "'arg'\"'\"'with'\"'\"'quotes' 'another'", "Multiple single quotes"),
    ]

    passed = 0
    failed = 0

    for input_val, expected, description in test_cases:
        result = escape_shell_args(input_val)
        status = "PASS" if result == expected else "FAIL"

        if result == expected:
            passed += 1
        else:
            failed += 1

        print(f"Test: {description}")
        print(f"  Input:    '{input_val}'")
        print(f"  Expected: {expected}")
        print(f"  Got:      {result}")
        print(f"  Status:   {status}")
        print()

    print(f"Results: {passed} passed, {failed} failed")
    return failed == 0


def test_shell_behavior():
    """
    Test how the escaped arguments would behave in a shell.
    This demonstrates the practical effect of the escaping.
    """
    print("\n=== Demonstrating shell behavior ===\n")

    test_inputs = [
        "domain.com",
        "arg1 arg2",
        "example.com password123",
    ]

    for input_val in test_inputs:
        escaped = escape_shell_args(input_val)
        print(f"Input: '{input_val}'")
        print(f"Command would be: bash -s -- {escaped}")
        print(f"  -> Script receives {len(input_val.split())} argument(s): {input_val.split()}")
        print()


def main():
    """Run all tests."""
    print("Testing escape_shell_args function")
    print("=" * 50)

    ok = test_escape_shell_args()
    test_shell_behavior()

    print("=" * 50)
    if ok:
        print("All tests passed!")
        return 0
    else:
        print("Some tests failed!")
        return 1


if __name__ == '__main__':
    sys.exit(main())
