#!/usr/bin/env python3
"""Build an exclusively published, verified local-beta DMG. Does not sign or notarize."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

import dmgbuild

from validate_dmg import validate

HERE = Path(__file__).resolve().parent
MACOS = HERE.parent.parent
ROOT = MACOS.parent.parent


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    # Do not resolve the final component: even a broken output symlink is a collision.
    output = args.output.absolute()
    if output.suffix != ".dmg" or os.path.lexists(output):
        parser.error("Choose a new .dmg path; existing artifacts are never overwritten.")
    run("python3", HERE.parent / "check_release.py", app, "--require-universal", "--channel", "Beta")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".cloakroll-dmg-", dir=output.parent) as temporary:
        work = Path(temporary)
        staged = work / "CloakRoll.app"
        run("/usr/bin/ditto", app, staged)
        guide = work / "Install Guide.txt"
        guide.write_bytes((HERE / "ReadMe.txt").read_bytes())
        run("/usr/bin/swift", HERE / "guide-icon.swift", guide)
        candidate = work / "candidate.dmg"
        dmgbuild.build_dmg(str(candidate), "CloakRoll", settings={
            "format": "UDZO", "filesystem": "HFS+", "compression_level": 9,
            "files": [str(staged), str(guide)], "symlinks": {"Applications": "/Applications"},
            "icon": str(staged / "Contents/Resources/CloakRoll.icns"),
            "background": str(ROOT / "assets/dmg/background.png"),
            "window_rect": ((240, 110), (760, 570)),
            "icon_locations": {"CloakRoll.app": (204, 282), "Applications": (556, 282),
                               "Install Guide.txt": (380, 464)},
            "icon_size": 96, "text_size": 12, "arrange_by": None,
            "show_icon_preview": False, "show_toolbar": False, "show_status_bar": False,
            "show_sidebar": False, "hide_extensions": ["CloakRoll.app", "Install Guide.txt"],
            "default_view": "icon-view", "include_icon_view_settings": True,
            "include_list_view_settings": False,
        }, lookForHiDPI=False)
        validate(candidate, app)
        # Same-filesystem link is atomic and fails if another invocation published this path.
        os.link(candidate, output)
    print(f"Created {output}. Local beta only; not notarized or published.")


if __name__ == "__main__":
    main()
