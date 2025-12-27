# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec file for Install Scripts GUI.

This spec file ensures that the data files (data_ru.json, data_en.json)
are bundled with the executable and can be found at runtime.

Usage:
    cd gui
    pyinstaller InstallScripts.spec
"""

import os

# Get the directory containing this spec file
spec_dir = os.path.dirname(os.path.abspath(SPEC))
parent_dir = os.path.dirname(spec_dir)

# Data files to include (source path, destination folder in bundle)
# Files are placed in the root of the bundle so get_base_path() can find them
datas = [
    (os.path.join(parent_dir, 'data_ru.json'), '.'),
    (os.path.join(parent_dir, 'data_en.json'), '.'),
]

a = Analysis(
    ['main.py'],
    pathex=[spec_dir],
    binaries=[],
    datas=datas,
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='InstallScripts',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
