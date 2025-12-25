#!/usr/bin/env python3
"""
Test script to verify ANSI escape sequence stripping functionality.

This script tests various ANSI escape sequences that might be present
in terminal output from shell scripts.
"""

import re


def strip_ansi_codes(text):
    """
    Strip ANSI escape codes from text.

    Removes all ANSI escape sequences including:
    - Color codes (e.g., \033[31m for red, \033[0m for reset)
    - Cursor movement codes
    - Screen clear codes
    - Other terminal control sequences

    Args:
        text: String that may contain ANSI escape sequences

    Returns:
        str: Clean text with all ANSI escape sequences removed
    """
    if not text:
        return text

    # Pattern matches all ANSI escape sequences:
    # - \033 or \x1b: ESC character
    # - \[: CSI (Control Sequence Introducer)
    # - [0-9;]*: Optional numeric parameters separated by semicolons
    # - [A-Za-z]: Command character (m for color, H for cursor, etc.)
    # Also matches OSC (Operating System Command) sequences: ESC ] ... BEL/ST
    ansi_pattern = re.compile(
        r'\x1b'           # ESC character
        r'(?:'            # Non-capturing group for alternatives
        r'\[[0-9;]*[A-Za-z]'  # CSI sequences (colors, cursor, etc.)
        r'|'              # OR
        r'\][^\x07]*\x07' # OSC sequences ending with BEL
        r'|'              # OR
        r'\][^\x1b]*\x1b\\' # OSC sequences ending with ST (ESC \)
        r'|'              # OR
        r'[PX^_][^\x1b]*\x1b\\' # DCS, SOS, PM, APC sequences
        r'|'              # OR
        r'[NOc]'          # Single character sequences (SS2, SS3, RIS)
        r')'
    )
    return ansi_pattern.sub('', text)


# Test cases
test_cases = [
    # Basic color codes
    ("\033[31mRed text\033[0m", "Red text"),
    ("\033[32mGreen text\033[0m", "Green text"),
    ("\033[1;34mBold blue\033[0m", "Bold blue"),

    # Complex color codes
    ("\033[38;5;196mExtended color\033[0m", "Extended color"),
    ("\033[48;2;255;0;0mTrue color bg\033[0m", "True color bg"),

    # Multiple color codes in one line
    ("\033[31mRed\033[0m and \033[32mGreen\033[0m", "Red and Green"),

    # Common script output with colors
    ("[ \033[32mOK\033[0m ] Service started", "[ OK ] Service started"),
    ("[\033[31mFAIL\033[0m] Service failed", "[FAIL] Service failed"),
    ("Processing... \033[33mwarning\033[0m", "Processing... warning"),

    # Cursor movement codes
    ("\033[2J\033[H", ""),  # Clear screen and move cursor to home
    ("Line 1\033[A", "Line 1"),  # Cursor up

    # Progress bars with escape sequences
    ("Progress: \033[K50%", "Progress: 50%"),

    # Line with only escape sequences
    ("\033[0m\033[K", ""),

    # Empty and None cases
    ("", ""),
    ("Plain text without escape codes", "Plain text without escape codes"),

    # Multiple newlines preserved
    ("Line 1\nLine 2\n\033[32mLine 3\033[0m\n", "Line 1\nLine 2\nLine 3\n"),

    # Hex escape character format
    ("\x1b[31mRed\x1b[0m", "Red"),

    # Bold, italic, underline
    ("\033[1mBold\033[0m", "Bold"),
    ("\033[3mItalic\033[0m", "Italic"),
    ("\033[4mUnderline\033[0m", "Underline"),

    # Combined attributes
    ("\033[1;4;31mBold underline red\033[0m", "Bold underline red"),
]

print("Testing strip_ansi_codes function:\n")
all_passed = True

for input_text, expected in test_cases:
    result = strip_ansi_codes(input_text)
    passed = result == expected

    if not passed:
        all_passed = False
        # Show escaped version for debugging
        input_repr = repr(input_text)
        result_repr = repr(result)
        expected_repr = repr(expected)
        print(f"FAIL:")
        print(f"  Input:    {input_repr}")
        print(f"  Expected: {expected_repr}")
        print(f"  Got:      {result_repr}")
        print()
    else:
        print(f"PASS: {repr(expected)}")

print(f"\n{'All tests passed!' if all_passed else 'Some tests failed!'}")
