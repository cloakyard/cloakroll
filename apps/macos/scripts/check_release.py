#!/usr/bin/env python3
"""Read-only checks of an actual built bundle; local signing is not distribution approval."""

import argparse
import plistlib
import re
import subprocess
import sys
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command(*arguments):
    result = subprocess.run(arguments, capture_output=True, check=True)
    return result.stdout, result.stderr


def plist(path):
    with path.open("rb") as source:
        return plistlib.load(source)


def check(app, distribution, build=None, channel=None):
    require(app.is_dir() and app.suffix == ".app", "Provide a built CloakRoll.app bundle.")
    info = plist(app / "Contents/Info.plist")
    require(info.get("CFBundleIdentifier") == "com.cloakyard.cloakroll", "Unexpected app identifier.")
    require(info.get("CFBundleExecutable") == "CloakRoll", "Unexpected executable.")
    require(info.get("LSMinimumSystemVersion") == "26.0", "Review the changed macOS deployment baseline.")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        require(re.fullmatch(r"\d+(?:\.\d+){0,2}", info.get(key, "")), f"Invalid version: {key}")
    require(info.get("CloakRollReleaseChannel") in {"Beta", "Development preview"}, "Unknown release channel.")
    if build:
        require(info["CFBundleVersion"] == build, "The built app has an unexpected build number.")
    if channel:
        require(info["CloakRollReleaseChannel"] == channel, "The built app has an unexpected release channel.")
    require(info.get("NSPhotoLibraryUsageDescription"), "The photo access explanation is missing.")
    require(not list(app.rglob("*.xctest")), "Test host bundle present; rebuild with the normal build action.")
    require((app / "Contents/Resources/Assets.car").is_file(), "Compiled assets are missing.")
    require((app / "Contents/Resources/CloakRoll.icns").is_file(), "Compatibility icon is missing.")
    root = Path(__file__).resolve().parents[3]
    resources = app / "Contents/Resources"
    require((resources / "LICENSE").read_bytes() == (root / "LICENSE").read_bytes(), "App license is missing or changed.")
    notices = Path(__file__).resolve().parents[1] / "App/Resources/ThirdPartyNotices/GRDB.txt"
    require((resources / "ThirdPartyNotices/GRDB.txt").read_bytes() == notices.read_bytes(),
            "GRDB license is missing or changed.")
    require(not list(app.rglob("*.debug.dylib")), "Debug library present in release bundle.")

    command("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    entitlements, _ = command("/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(app))
    expected = plist(Path(__file__).resolve().parents[1] / "App/Resources/CloakRoll.entitlements")
    require(plistlib.loads(entitlements) == expected,
            "Signed entitlements differ from the reviewed source (including possible test/debug permissions).")
    _, signature = command("/usr/bin/codesign", "-dv", "--verbose=4", str(app))
    signature = signature.decode()
    require(re.search(r"flags=.*\([^\n]*runtime", signature), "Hardened runtime is missing.")
    architectures, _ = command("/usr/bin/lipo", "-archs", str(app / "Contents/MacOS/CloakRoll"))
    architectures = architectures.decode().strip()
    require(architectures.split() == ["arm64"], "CloakRoll requires an Apple silicon-only (arm64) executable.")
    build_info, _ = command("/usr/bin/xcrun", "vtool", "-show-build", str(app / "Contents/MacOS/CloakRoll"))
    require(re.search(r"minos\s+26\.0(?:\.0)?(?:\s|$)", build_info.decode()),
            "The executable must target macOS 26.0, matching the bundle requirement.")

    privacy = plist(app / "Contents/Resources/PrivacyInfo.xcprivacy")
    manifests = list((app / "Contents/Resources").rglob("PrivacyInfo.xcprivacy"))
    require(any("GRDB_GRDB.bundle" in str(path) for path in manifests), "GRDB privacy manifest is missing.")
    for path in manifests:
        entry = plist(path)
        require(entry.get("NSPrivacyTracking") is False, "Unexpected tracking declaration.")
        require(entry.get("NSPrivacyTrackingDomains") == [], "Unexpected tracking domains.")
        require(entry.get("NSPrivacyCollectedDataTypes") == [], "Unexpected data collection declaration.")
    entries = privacy.get("NSPrivacyAccessedAPITypes", [])
    reasons = {entry["NSPrivacyAccessedAPIType"]: set(entry["NSPrivacyAccessedAPITypeReasons"]) for entry in entries}
    require(len(entries) == len(reasons) and reasons == {
        "NSPrivacyAccessedAPICategoryDiskSpace": {"E174.1"},
        "NSPrivacyAccessedAPICategoryFileTimestamp": {"C617.1", "3B52.1"},
        "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1"},
    }, "Required-reason declarations differ from the reviewed uses.")

    print(f"Verified CloakRoll {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}); {architectures}.")
    print("Bundle, signature, sandbox entitlements, hardened runtime, icons and privacy manifests pass.")
    if distribution:
        require("Authority=Developer ID Application:" in signature, "Distribution requires a Developer ID Application signature.")
        command("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", str(app))
        command("/usr/bin/xcrun", "stapler", "validate", str(app))
        print("Developer ID, Gatekeeper assessment and stapled notarization ticket pass.")
    else:
        print("Local build checks only. Developer ID, notarization and hardware acceptance are separate release gates.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--require-distribution", action="store_true",
                        help="Also require Developer ID, Gatekeeper acceptance and a stapled notarization ticket.")
    parser.add_argument("--build", help="Require this exact CFBundleVersion.")
    parser.add_argument("--channel", choices=["Beta", "Development preview"])
    arguments = parser.parse_args()
    try:
        check(arguments.app.resolve(), arguments.require_distribution,
              arguments.build, arguments.channel)
    except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        print(f"Release check failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr.decode(errors="replace").strip(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
