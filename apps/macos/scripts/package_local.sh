#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/to/CloakRoll.app /path/to/local-preview.zip" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
app="$1"
archive="$2"
if [[ "$archive" != *.zip || -e "$archive" || -L "$archive" ]]; then
    echo "Choose a new .zip path; existing artifacts are never overwritten." >&2
    exit 2
fi
mkdir -p "$(dirname "$archive")"
package_dir="$(mktemp -d "$(dirname "$archive")/.cloakroll-package.XXXXXX")"
trap 'rm -rf -- "$package_dir"' EXIT

/usr/bin/ditto "$app" "$package_dir/CloakRoll.app"
python3 "$script_dir/check_release.py" "$package_dir/CloakRoll.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$package_dir/CloakRoll.app" "$package_dir/archive.zip"
/usr/bin/unzip -tq "$package_dir/archive.zip"
# Exclusive publication protects an artifact another invocation may have created meanwhile.
/bin/ln "$package_dir/archive.zip" "$archive"
/usr/bin/shasum -a 256 "$archive"
echo "Local preview archive created. This command does not sign, notarize or publish a release."
