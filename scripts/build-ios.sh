#!/usr/bin/env bash
# macOS 本地构建 iOS 包（Ad-Hoc）。Windows 本机无法运行；CI 用 .github/workflows/ios-build.yml。
# 用法：
#   export VCPKG_ROOT=/path/to/vcpkg
#   export VCPKG_INSTALLED="$VCPKG_ROOT/installed/arm64-ios"
#   bash scripts/build-ios.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${VCPKG_ROOT:?请设置 VCPKG_ROOT}"
: "${VCPKG_INSTALLED:?请设置 VCPKG_INSTALLED（arm64-ios installed 目录）}"

OUT="$ROOT/.build/ios"
mkdir -p "$OUT"

# 确保 vcpkg 依赖已装
"$VCPKG_ROOT/vcpkg" install curl:arm64-ios openssl:arm64-ios --classic --clean-after-build

xcodebuild -project "$ROOT/ios/ChatboxIOS.xcodeproj" \
  -scheme ChatboxIOS \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/ChatboxIOS.xcarchive" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  archive 2>&1 | tee "$OUT/archive.log"

cat > "$OUT/ExportOptions.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>ad-hoc</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
  <key>uploadSymbols</key><false/>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$OUT/ChatboxIOS.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/ipa" 2>&1 | tee "$OUT/export.log"

echo "=== 完成：$OUT/ipa ==="
ls -la "$OUT/ipa"
