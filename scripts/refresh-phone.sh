#!/usr/bin/env bash
set -eo pipefail

# -----------------------------------------------------------------------------
# Derivee - Physical iPhone Local Refresh & Sideload Script
# 
# Rebuilds Derivee with automatic profile re-signing and installs it over USB
# or Wi-Fi to your physical iPhone, resetting the 7-day personal provisioning timer.
# -----------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$REPO_ROOT/DeriveeNative/Derivee.xcodeproj"
SCHEME="Derivee"
CONFIGURATION="Debug"
BUNDLE_ID="com.derivee.Derivee"

echo "=========================================================="
echo "  📱 Derivee Local Phone Refresh & Deployment Tool        "
echo "=========================================================="

# 1. Discover Paired iPhone
echo "🔍 Scanning for connected, paired iOS devices..."

TEMP_DEVICE_JSON=$(mktemp /tmp/derivee_devices.XXXXXX.json)
trap 'rm -f "$TEMP_DEVICE_JSON"' EXIT

xcrun devicectl list devices \
  --filter "hardwareProperties.platform == 'iOS' AND state == 'available (paired)'" \
  --json-output "$TEMP_DEVICE_JSON" > /dev/null 2>&1 || true

DEVICE_INFO=$(python3 -c "
import json, sys
try:
    with open('$TEMP_DEVICE_JSON') as f:
        data = json.load(f)
    devices = data.get('result', {}).get('devices', [])
    if not devices:
        sys.exit(1)
    # Pick first available paired iOS device
    dev = devices[0]
    dev_id = dev.get('identifier', '')
    dev_name = dev.get('deviceProperties', {}).get('name', 'Unknown iPhone')
    model = dev.get('hardwareProperties', {}).get('marketingProductName', 'iPhone')
    print(f'{dev_id}\t{dev_name}\t{model}')
except Exception:
    sys.exit(1)
" 2>/dev/null || true)

if [ -z "$DEVICE_INFO" ]; then
  echo "❌ No paired, available iPhone detected."
  echo ""
  echo "Troubleshooting Checklist:"
  echo "  1. Unlock your iPhone and connect it via USB-C/Lightning (or join the same Wi-Fi network)."
  echo "  2. Ensure 'Developer Mode' is enabled on your iPhone:"
  echo "     Settings > Privacy & Security > Developer Mode -> ON (reboot if prompted)."
  echo "  3. Open Xcode once and ensure your iPhone appears in Window > Devices and Simulators."
  exit 1
fi

DEVICE_ID=$(echo "$DEVICE_INFO" | cut -f1)
DEVICE_NAME=$(echo "$DEVICE_INFO" | cut -f2)
DEVICE_MODEL=$(echo "$DEVICE_INFO" | cut -f3)

echo "✅ Target Device Found:"
echo "   • Name:  $DEVICE_NAME"
echo "   • Model: $DEVICE_MODEL"
echo "   • UDID:  $DEVICE_ID"
echo ""

# 2. Build & Re-provision with automatic signing
echo "⚙️  Building Derivee and renewing provisioning profile..."

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -configuration "$CONFIGURATION" \
  -allowProvisioningUpdates \
  build | xcbeautify 2>/dev/null || xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -configuration "$CONFIGURATION" \
  -allowProvisioningUpdates \
  build

# Locate built Derivee.app
BUILD_DIR=$(xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -configuration "$CONFIGURATION" \
  -showBuildSettings 2>/dev/null | awk -F ' = ' '/TARGET_BUILD_DIR/ {print $2}' | head -n 1)

APP_PATH="$BUILD_DIR/Derivee.app"

if [ ! -d "$APP_PATH" ]; then
  echo "❌ Error: Could not locate built app at: $APP_PATH"
  exit 1
fi

echo "✅ Build succeeded: $APP_PATH"
echo ""

# 3. Install App to Device
echo "📦 Installing refreshed Derivee onto $DEVICE_NAME..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "✅ App successfully installed and profile refreshed!"
echo ""

# 4. Attempt to launch the app
echo "🚀 Launching Derivee on $DEVICE_NAME..."
if xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID" 2>&1; then
  echo "✅ Derivee launched successfully!"
else
  echo ""
  echo "⚠️  Note on First Launch / Security Profile Trust:"
  echo "If your iPhone displays an 'Untrusted Developer' prompt or refused to launch:"
  echo "  1. On your iPhone, open: Settings > General > VPN & Device Management"
  echo "  2. Under 'DEVELOPER APP', tap your Apple ID email"
  echo "  3. Tap 'Trust' and confirm"
  echo "  4. Tap the Derivee icon on your home screen to open!"
fi

echo ""
echo "=========================================================="
echo "🎉 Done! Your 7-day provisioning window is now reset."
echo "   Run './scripts/refresh-phone.sh' anytime to refresh."
echo "=========================================================="
