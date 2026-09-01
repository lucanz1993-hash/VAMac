# -*- mode: python ; coding: utf-8 -*-
# Variante macOS di FC_Manager.spec (Windows): produce un bundle .app
# invece di un .exe. L'icona .icns viene generata da assets/icona-master.png
# nello step precedente del workflow CI (vedi .github/workflows/build-macos.yml),
# perche' PyInstaller su macOS richiede .icns e non accetta .ico.

a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('assets', 'assets'),
        ('qml', 'qml'),
    ],
    hiddenimports=[
        'PyQt6.QtQml',
        'PyQt6.QtQuick',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='FC Manager',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
)

app = BUNDLE(
    exe,
    name='FC Manager.app',
    icon='assets/icona.icns',
    bundle_identifier='it.lbcoaching.fcmanager',
    info_plist={
        'NSHighResolutionCapable': 'True',
        'CFBundleShortVersionString': '1.0.0',
    },
)
