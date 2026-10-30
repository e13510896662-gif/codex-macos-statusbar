#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --product CodexFlow --build-system native
bin_dir="$(swift build -c release --show-bin-path --build-system native)"
app_dir="${CODEX_FLOW_OUTPUT_DIR:-dist}/Codex Mac 状态栏.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/CodexFlow" "$app_dir/Contents/MacOS/CodexFlow"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CodexFlow</string>
  <key>CFBundleIdentifier</key><string>local.codexflow.menubar</string>
  <key>CFBundleName</key><string>Codex Mac 状态栏</string>
  <key>CFBundleDisplayName</key><string>Codex Mac 状态栏</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Codex Flow · Personal menu bar monitor</string>
</dict></plist>
PLIST
# File Provider can attach Finder metadata to new bundles in Documents.
xattr -cr "$app_dir"
# Removing all attributes can cause File Provider to reattach FinderInfo;
# remove that one attribute explicitly immediately before signing.
xattr -d com.apple.FinderInfo "$app_dir" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$app_dir"
codesign --verify --strict "$app_dir"
printf '已构建：%s/%s\n' "$(cd "$(dirname "$app_dir")" && pwd)" "$(basename "$app_dir")"
