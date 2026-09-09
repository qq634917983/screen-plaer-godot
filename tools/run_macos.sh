#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo "ARM64 macOS is required." >&2; exit 1; }
for dependency in cef_artifacts/gdcef.gdextension cef_artifacts/macos/libgdcef.dylib; do
  [[ -f "$dependency" ]] || { echo "Missing $dependency. Run ./tools/build_macos.sh --with-cef" >&2; exit 1; }
done
godot="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
[[ -x "$godot" ]] || { echo "Set GODOT_BIN to the Godot executable." >&2; exit 1; }
[[ -f "bin/libgodot_mpv.macos.$(uname -m).dylib" ]] || {
  echo "Build the Mac backend first: ./tools/build_macos.sh --with-cef" >&2
  exit 1
}
# Fresh clones need script class/UID registration before the main scene loads.
"$godot" --headless --editor --path "$PWD" --import --quit
exec "$godot" --path "$PWD" "$@"
