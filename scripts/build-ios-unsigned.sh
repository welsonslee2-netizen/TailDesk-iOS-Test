#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/mobile/ios"
OUTPUT_DIR="$ROOT/artifacts/ios"
DERIVED_DATA="$RUNNER_TEMP/TailDeskDerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/TailDesk.app"
PAYLOAD_DIR="$RUNNER_TEMP/TailDeskPayload/Payload"
IPA_PATH="$OUTPUT_DIR/TailDesk-unsigned.ipa"

rm -rf "$DERIVED_DATA" "$RUNNER_TEMP/TailDeskPayload"
mkdir -p "$OUTPUT_DIR" "$PAYLOAD_DIR"

cd "$PROJECT_DIR"
xcodegen generate
xcodebuild \
  -project TailDeskMobile.xcodeproj \
  -scheme TailDeskMobile \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM='' \
  clean build

test -d "$APP_PATH"
test -x "$APP_PATH/TailDesk"
/usr/bin/plutil -lint "$APP_PATH/Info.plist"
/usr/bin/plutil -extract CFBundleIdentifier raw "$APP_PATH/Info.plist" | grep -Fx 'com.taildesk.mobile'
/usr/bin/plutil -extract CFBundleDisplayName raw "$APP_PATH/Info.plist" | grep -Fx 'TailDesk'
/usr/bin/plutil -extract CFBundleExecutable raw "$APP_PATH/Info.plist" | grep -Fx 'TailDesk'
/usr/bin/plutil -extract CFBundlePackageType raw "$APP_PATH/Info.plist" | grep -Fx 'APPL'
/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_PATH/Info.plist" | grep -Fx '0.12'
/usr/bin/plutil -extract CFBundleVersion raw "$APP_PATH/Info.plist" | grep -Fx '12'
/usr/bin/plutil -extract MinimumOSVersion raw "$APP_PATH/Info.plist" | grep -Fx '16.0'
/usr/bin/plutil -extract NSLocalNetworkUsageDescription raw "$APP_PATH/Info.plist" | grep -F 'Tailscale'
/usr/bin/plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoads raw "$APP_PATH/Info.plist" | grep -Fx 'true'
/usr/bin/lipo -info "$APP_PATH/TailDesk"
test -f "$APP_PATH/AppIcon60x60@2x.png"

cp -R "$APP_PATH" "$PAYLOAD_DIR/"
cd "$(dirname "$PAYLOAD_DIR")"
/usr/bin/zip -qry "$IPA_PATH" Payload
/usr/bin/unzip -tq "$IPA_PATH"

cd "$OUTPUT_DIR"
/usr/bin/shasum -a 256 TailDesk-unsigned.ipa > TailDesk-unsigned.ipa.sha256
{
  echo "Built at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  sw_vers
  xcodebuild -version
  swift --version
  /usr/bin/file "$APP_PATH/TailDesk"
} > build-info.txt

echo "Created $IPA_PATH"

