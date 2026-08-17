# PyInstaller spec — builds "YT Channel Scraper.app". Driven by build-app.sh, which
# stages vendor/ first; running pyinstaller on this file directly assumes that is done.
#
# yt-dlp is frozen in like any other dependency, which is what drags in the long tail of
# stdlib modules its extractors import. The in-app updater overrides it at runtime with a
# sys.meta_path finder rather than by leaving it out of the bundle; see app.py.

from PyInstaller.utils.hooks import collect_submodules

block_cipher = None

a = Analysis(
    ["app.py"],
    pathex=[],
    binaries=[],
    datas=[
        ("templates", "templates"),
        ("vendor", "vendor"),  # static ffmpeg + ffprobe
    ],
    # yt-dlp resolves extractors lazily, so nothing static points at most of them.
    hiddenimports=collect_submodules("yt_dlp"),
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "unittest", "pydoc_data"],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="YT Channel Scraper",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="YT Channel Scraper",
)

app = BUNDLE(
    coll,
    name="YT Channel Scraper.app",
    icon="icon.icns",
    bundle_identifier="com.moregroup.ytchannelscraper",
    info_plist={
        "CFBundleName": "YT Channel Scraper",
        "CFBundleDisplayName": "YT Channel Scraper",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1.0.0",
        "NSHighResolutionCapable": True,
        # The UI is a browser tab, so the process owns no window. Without this it would
        # get a Dock icon that cannot be quit — macOS would send it an Apple Event that
        # a plain Python process never answers, and report it as unresponsive. Quitting
        # happens from the page instead.
        "LSUIElement": True,
        "LSMinimumSystemVersion": "11.0",
        "NSHumanReadableCopyright": "Local use only.",
    },
)
