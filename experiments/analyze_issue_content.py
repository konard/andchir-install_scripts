#!/usr/bin/env python3
"""
Analyze the actual content from the issue to understand what characters need to be stripped.
"""

# Example content from the issue comment (with escape sequences in different representations)
# The ^[ in the issue is actually the ESC character (0x1B)
# The ^@ is the NULL character (0x00)
# The ^H is backspace (0x08)
# The ^J is newline (0x0A)

# Simulating what the actual content might look like
example_patterns = [
    # Pattern 1: ESC [ followed by color codes (CSI sequences)
    ('\x1b[0;36m', 'ESC[0;36m - cyan color'),
    ('\x1b[0m', 'ESC[0m - reset'),
    ('\x1b[1;37m', 'ESC[1;37m - bold white'),
    ('\x1b[H', 'ESC[H - cursor home'),
    ('\x1b[J', 'ESC[J - erase display'),
    ('\x1b[0;32m', 'ESC[0;32m - green'),

    # Pattern 2: NULL characters
    ('\x00', 'NULL character'),

    # Pattern 3: Other control characters
    ('\x08', 'Backspace'),
]

import re

def strip_ansi_codes_current(text):
    """Current implementation from app.py"""
    if not text:
        return text

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


def strip_ansi_codes_improved(text):
    """Improved implementation that also handles NULL and other control characters"""
    if not text:
        return text

    # Pattern matches all ANSI escape sequences:
    # - \x1b: ESC character
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
    result = ansi_pattern.sub('', text)

    # Also strip NULL characters and other non-printable control characters
    # except for common whitespace (tab, newline, carriage return)
    # Control characters are 0x00-0x1F and 0x7F
    # We keep: 0x09 (tab), 0x0A (newline), 0x0D (carriage return)
    control_pattern = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]')
    result = control_pattern.sub('', result)

    return result


# Test with actual content similar to the issue
test_content = (
    "Starting installation of 'pocketbase' on 109.199.116.127...\n"
    "Connecting to 109.199.116.127:22 via SSH...\n"
    "Executing script: pocketbase\n\n"
    "\x1b[0;36m╔══════════════════════════════════════════════════════════════════════════════╗\x1b[0m\n"
    "\x1b[0;36m║\x1b[0m  \x1b[1m\x1b[1;37mDomain Configuration\x1b[0m\n"
    "\x1b[0;36m╚══════════════════════════════════════════════════════════════════════════════╝\x1b[0m\n\n"
    "\x1b[0;32m✔\x1b[0m \x1b[0;32mDomain configured: installer.api2app.org\x1b[0m\n"
    "\x1b[H\x1b[J"  # Screen clear
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"  # NULL characters
    "\x1b[0;36m   ╔═══════════════════════════════════════════════════════════════════════════╗\x1b[0m\n"
)

print("Original content:")
print("=" * 60)
print(repr(test_content[:500]))
print()

print("After current strip_ansi_codes:")
print("=" * 60)
current_result = strip_ansi_codes_current(test_content)
print(repr(current_result[:500]))
print()
print("NULL characters remaining:", current_result.count('\x00'))

print()
print("After improved strip_ansi_codes:")
print("=" * 60)
improved_result = strip_ansi_codes_improved(test_content)
print(repr(improved_result[:500]))
print()
print("NULL characters remaining:", improved_result.count('\x00'))

print()
print("Clean readable output:")
print("=" * 60)
print(improved_result[:500])
