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
"$VCPKG_ROOT/vcpkg" install curl:arm64-ios openssl:arm64-ios --classic \
  --overlay-triplets="$ROOT/cmake/triplets" --clean-after-build

xcodebuild -project "$ROOT/ios/ChatboxIOS.xcodeproj" \
  -scheme ChatboxIOS \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/ChatboxIOS.xcarchive" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  archive 2>&1 | tee "$OUT/archive.log"

# archive 未签名（CODE_SIGNING_ALLOWED=NO），-exportArchive 需开发者 Team，
# 因此手动组 ipa + ad-hoc 签名（装上需 sideload 工具重签）。
APP="$OUT/ChatboxIOS.xcarchive/Products/Applications/ChatboxIOS.app"
test -d "$APP" || { echo "找不到 ChatboxIOS.app"; exit 1; }
codesign --force --deep --sign - --timestamp=none "$APP" || echo "警告：ad-hoc 签名失败，产物为未签名 ipa"
rm -rf "$OUT/ipa" && mkdir -p "$OUT/ipa/Payload"
cp -R "$APP" "$OUT/ipa/Payload/"
( cd "$OUT/ipa" && zip -qry "ChatboxIOS-adhoc.ipa" Payload )

echo "=== 完成：$OUT/ipa ==="
ls -la "$OUT/ipa"
