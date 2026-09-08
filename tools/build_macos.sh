#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "Run this script natively on ARM64 macOS." >&2
  exit 1
fi
for tool in git cmake brew python3; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. See doc/MACOS.md." >&2; exit 1; }
done
root="$PWD"
build_dir="${SCREENPLAYER_BUILD_DIR:-$root/.build}"
mkdir -p "$build_dir"
touch "$build_dir/.gdignore"
cpp="$build_dir/godot-cpp"
cpp_commit=e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77
if [[ ! -d "$cpp/.git" ]]; then
  git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp.git "$cpp"
fi
[[ "$(git -C "$cpp" rev-parse HEAD)" == "$cpp_commit" ]] || { echo "Unexpected godot-cpp revision" >&2; exit 1; }
cmake -S native/mpv -B "$build_dir/mpv" \
  -DGODOT_CPP_PATH="$cpp" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$(brew --prefix)"
cmake --build "$build_dir/mpv" --parallel "$(sysctl -n hw.logicalcpu)"
codesign --force --sign - "bin/libgodot_mpv.macos.$(uname -m).dylib"
if [[ "${1:-}" == --with-cef ]]; then
  [[ -d /Applications/Xcode.app ]] || { echo "CEF requires full Xcode." >&2; exit 1; }
  python3 -m venv "$build_dir/venv"
  "$build_dir/venv/bin/python" -m pip install -r tools/macos-requirements.txt
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export PATH="$build_dir/venv/bin:$PATH"
  "$build_dir/venv/bin/python" tools/build_cef_macos.py "$cpp"
fi
echo "Build complete. Run ./tools/run_macos.sh"
