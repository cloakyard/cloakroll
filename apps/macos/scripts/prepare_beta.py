#!/usr/bin/env python3
"""Build a dated universal beta from a clean commit, with logs and artifact provenance."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
MACOS = HERE.parent
ROOT = MACOS.parent.parent
sys.path.insert(0, str(HERE / "dmg"))
from validate_dmg import inventory  # noqa: E402


def output(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default=datetime.now(ZoneInfo("Asia/Kolkata")).strftime("%Y%m%d"),
                        help="YYYYMMDD, optionally .N for another build that day (India time).")
    args = parser.parse_args()
    if not re.fullmatch(r"\d{8}(?:\.[1-9]\d*)?", args.build):
        parser.error("Build must be YYYYMMDD or YYYYMMDD.N.")
    datetime.strptime(args.build.split(".")[0], "%Y%m%d")
    if output("git", "status", "--porcelain"):
        parser.error("Commit source changes before preparing a beta so provenance is reproducible.")
    version = "0.1.0"
    release = MACOS / "build" / f"Beta-{version}-{args.build}"
    release.mkdir(parents=True, exist_ok=False)
    logs = release / "logs"
    logs.mkdir()
    environment = dict(os.environ, GIT_CONFIG_COUNT="0")

    def run(label, command, cwd=MACOS):
        print(f"{label}… ({logs / (label + '.log')})", flush=True)
        with (logs / (label + ".log")).open("w") as log:
            subprocess.run([str(part) for part in command], cwd=cwd, env=environment,
                           stdout=log, stderr=subprocess.STDOUT, check=True)

    run("core-tests", ["swift", "test"], MACOS / "Packages/CloakRollCore")
    run("generate", ["xcodegen", "generate"])
    run("lint", ["swiftlint", "--strict"])
    base = ["xcodebuild", "-project", "CloakRoll.xcodeproj", "-scheme", "CloakRoll"]
    debug = base + ["-destination", "platform=macOS,arch=arm64", "-configuration", "Debug",
                    "-derivedDataPath", release / "Debug"]
    run("app-tests", debug + ["test"])
    run("debug-build", debug + ["build"])
    run("release-build", base + ["-destination", "platform=macOS", "-configuration", "Release",
        "-derivedDataPath", release / "Release", "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO",
        f"MARKETING_VERSION={version}", f"CURRENT_PROJECT_VERSION={args.build}",
        "CLOAKROLL_RELEASE_CHANNEL=Beta", "build"])
    app = release / "Release/Build/Products/Release/CloakRoll.app"
    run("bundle-check", [sys.executable, HERE / "check_release.py", app, "--require-universal",
                         "--build", args.build, "--channel", "Beta"])
    dmg = release / f"CloakRoll-v{version}-beta.{args.build}.dmg"
    run("dmg", [sys.executable, HERE / "dmg/make_dmg.py", app, dmg])
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)], capture_output=True,
                               text=True, check=True).stderr
    counts = {}
    for label in ("core-tests", "app-tests"):
        counts[label] = sum(int(n) for n in re.findall(r"Test run with (\d+) tests.*passed", (logs / f"{label}.log").read_text()))
        if not counts[label]:
            raise ValueError(f"No successful test summary found in {label}.")
    def sha(path):
        with path.open("rb") as stream:
            return hashlib.file_digest(stream, "sha256").hexdigest()
    manifest = {
        "product": "CloakRoll", "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
        "channel": info["CloakRollReleaseChannel"], "sourceCommit": output("git", "rev-parse", "HEAD"),
        "createdAt": datetime.now(ZoneInfo("UTC")).isoformat(), "published": False,
        "architectures": output("lipo", "-archs", str(app / "Contents/MacOS/CloakRoll")).split(),
        "minimumMacOS": info["LSMinimumSystemVersion"],
        "hostMacOS": output("sw_vers", "-productVersion"), "xcode": output("xcodebuild", "-version"),
        "signing": "ad-hoc" if "Signature=adhoc" in signature else "See bundle-check log",
        "notarized": False, "automatedTests": counts,
        "artifact": {"name": dmg.name, "bytes": dmg.stat().st_size, "sha256": sha(dmg)},
        "backgroundSHA256": sha(ROOT / "assets/dmg/background.png"),
        "nativeAndHardwareValidation": "See dated release audit; not performed by this script.",
    }
    (release / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (release / "app-inventory.json").write_text(json.dumps(inventory(app), indent=2) + "\n")
    (release / "SHA256SUMS.txt").write_text("".join(
        f"{sha(path)}  {path.name}\n" for path in [dmg, release / "build-manifest.json", release / "app-inventory.json"]))
    print(f"Beta prepared: {dmg}\nNo GitHub release was published.", flush=True)


if __name__ == "__main__":
    main()
