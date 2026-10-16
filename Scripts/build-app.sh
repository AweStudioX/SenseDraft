#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
export XDG_CACHE_HOME="$project_dir/.build/cache"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
swift build --disable-sandbox

bundle="$project_dir/build/SenseDraft.app"
mkdir -p "$bundle/Contents/MacOS"
binary="$project_dir/.build/debug/SenseDraftMac"
packaged_binary="$bundle/Contents/MacOS/SenseDraftMac"
packaged_plist="$bundle/Contents/Info.plist"
metadata_dir="$bundle/Contents/Resources"
source_hash_file="$metadata_dir/bundle-inputs.sha256"
identity_file="$metadata_dir/signing-identity.txt"
identity="${SENSEDRAFT_SIGN_IDENTITY:--}"
source_hash="$(shasum -a 256 "$binary" "$project_dir/Resources/AppIcon.png" "$project_dir/Resources/StatusBar.png" | shasum -a 256 | cut -d ' ' -f 1)"

# Leave an unchanged app bundle untouched. With ad hoc signing, the designated
# requirement is a code hash, so every changed binary needs a fresh macOS
# Accessibility grant. Re-signing needlessly makes development harder.
if [[ -f "$packaged_binary" && -f "$packaged_plist" && -f "$metadata_dir/AppIcon.png" && -f "$source_hash_file" && -f "$identity_file" ]] &&
   [[ "$(cat "$source_hash_file")" == "$source_hash" ]] &&
   [[ "$(cat "$identity_file")" == "$identity" ]] &&
   cmp -s "$project_dir/Resources/Info.plist" "$packaged_plist" &&
   codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
    echo "Unchanged app bundle; preserving its existing signature."
else
    cp "$binary" "$packaged_binary"
    cp "$project_dir/Resources/Info.plist" "$packaged_plist"
    mkdir -p "$metadata_dir"
    cp "$project_dir/Resources/StatusBar.png" "$metadata_dir/StatusBar.png"
    cp "$project_dir/Resources/AppIcon.png" "$metadata_dir/AppIcon.png"
    iconset="$(mktemp -d "${TMPDIR:-/tmp}/SenseDraft.iconset.XXXXXX")"
    iconset="$iconset/SenseDraft.iconset"
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$project_dir/Resources/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        double_size=$((size * 2))
        sips -z "$double_size" "$double_size" "$project_dir/Resources/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns --output "$metadata_dir/SenseDraft.icns" "$iconset"
    rm -rf "$(dirname "$iconset")"
    rm -f "$metadata_dir/source-binary.sha256"
    printf '%s\n' "$source_hash" > "$source_hash_file"
    printf '%s\n' "$identity" > "$identity_file"
    codesign --force --sign "$identity" --timestamp=none "$bundle"
    if [[ "$identity" == "-" ]]; then
        echo "Ad hoc signature changed: macOS may require a fresh Accessibility grant for this build." >&2
    fi
fi
test -x "$bundle/Contents/MacOS/SenseDraftMac"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$bundle/Contents/Info.plist")" = "com.kaaaaai.SenseDraft"
echo "$bundle"
