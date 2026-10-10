#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
export XDG_CACHE_HOME="$project_dir/.build/cache"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
swift build --disable-sandbox

bundle="$project_dir/build/SenseDraft.app"
mkdir -p "$bundle/Contents/MacOS"
cp "$project_dir/.build/debug/SenseDraftMac" "$bundle/Contents/MacOS/SenseDraftMac"
cp "$project_dir/Resources/Info.plist" "$bundle/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$bundle"
test -x "$bundle/Contents/MacOS/SenseDraftMac"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$bundle/Contents/Info.plist")" = "com.kaaaaai.SenseDraft"
echo "$bundle"
