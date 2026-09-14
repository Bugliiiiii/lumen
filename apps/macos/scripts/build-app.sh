#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
artifact_dir="$project_dir/artifacts"
app_dir="$artifact_dir/Lumen.app"

cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
export SWIFT_MODULE_CACHE_PATH="$project_dir/.build/module-cache"

swift_args=(-c release)
if [[ -n "${MONITOR_SWITCH_SDK:-}" ]]; then
  export SDKROOT="$MONITOR_SWITCH_SDK"
  swift_args+=(--sdk "$MONITOR_SWITCH_SDK")
fi

swift build "${swift_args[@]}" --product MonitorSwitchMac
bin_dir="$(swift build "${swift_args[@]}" --show-bin-path)"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/MonitorSwitchMac" "$app_dir/Contents/MacOS/MonitorSwitchMac"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
if [[ -f "$project_dir/Resources/AppIcon.icns" ]]; then
  cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$app_dir"

# --- Package DMG ---
dmg_path="$artifact_dir/Lumen-macOS-arm64.dmg"
dmg_staging="$artifact_dir/.dmg-staging"

rm -rf "$dmg_staging" "$dmg_path"
mkdir -p "$dmg_staging"
cp -R "$app_dir" "$dmg_staging/"
ln -s /Applications "$dmg_staging/Applications"

hdiutil create -volname "Lumen" \
  -srcfolder "$dmg_staging" \
  -ov -format UDZO \
  -imagekey zlib-level=9 \
  "$dmg_path"

rm -rf "$dmg_staging"

echo "$app_dir"
echo "$dmg_path"
