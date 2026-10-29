#!/bin/bash
# Same Air drag-to-Applications composition as CloakDrop, without Finder automation.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
python="${DMG_PYTHON:-$script_dir/../../build/dmg-tools/bin/python}"
if [[ ! -x "$python" ]]; then
    echo "Install the pinned DMG tools first; see docs/RELEASE.md." >&2
    exit 2
fi
exec "$python" "$script_dir/make_dmg.py" "$@"
