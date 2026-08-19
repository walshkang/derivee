#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Dérivée Demo Video Recording & GPX Playback Automation
# Architecture & Performance Telemetry Showcase
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIMULATOR_NAME="${1:-booted}"
TMP_RAW="/tmp/derivee_demo_raw.mp4"
OUTPUT_FINAL="${SCRIPT_DIR}/derivee_demo_final.mp4"
GPX_PATH="$(cd "${SCRIPT_DIR}/../../DeriveeNative" && pwd)/NYC_Walk.gpx"

echo "======================================================================"
echo "🎬 Dérivée Demo Video Recording Automation"
echo "======================================================================"
echo "📱 Target Simulator: ${SIMULATOR_NAME}"
echo "🗺️ GPX Track Path:   ${GPX_PATH}"
echo "📁 Output Video:     ${OUTPUT_FINAL}"
echo "======================================================================"

# 1. Bring Simulator to Front & Pre-grant Location Privacy Permissions
echo "==> [1/4] Focusing Simulator and granting CoreLocation permissions..."
open -a Simulator
xcrun simctl privacy "${SIMULATOR_NAME}" grant location-always com.derivee.Derivee 2>/dev/null || true

# 2. Terminate Stale App Process, Set Appearance & Launch Fresh
echo "==> [2/4] Setting Day Mode, pristine status bar, initial Columbus Circle fix, and launching Dérivée..."
xcrun simctl terminate "${SIMULATOR_NAME}" com.derivee.Derivee 2>/dev/null || true
xcrun simctl ui "${SIMULATOR_NAME}" appearance light 2>/dev/null || true
xcrun simctl location "${SIMULATOR_NAME}" set 40.768075,-73.981897 2>/dev/null || true
xcrun simctl status_bar "${SIMULATOR_NAME}" override \
    --time "9:41" \
    --dataNetwork "wifi" \
    --wifiMode "active" \
    --wifiBars 3 \
    --cellularMode "active" \
    --cellularBars 4 \
    --batteryState "charged" \
    --batteryLevel 100 2>/dev/null || true

xcrun simctl launch "${SIMULATOR_NAME}" com.derivee.Derivee -isTrackingEnabled YES -selectedBasemapTheme day 2>/dev/null || true
sleep 2

# 3. Start High-Definition Screen Recording to /tmp (avoids CoreSimulator sandbox permissions on external drives)
echo "==> [3/4] Initializing 60fps screen recording..."
rm -f "${TMP_RAW}"
xcrun simctl io "${SIMULATOR_NAME}" recordVideo \
    --codec=h264 \
    --mask=black \
    --force \
    "${TMP_RAW}" &
RECORD_PID=$!

# 4. Start Waypoint Walk from GPX
echo "==> [4/4] Starting GPX waypoint simulation (speed: 3.5 m/s)..."
grep -o 'lat="[^"]*" lon="[^"]*"' "${GPX_PATH}" | sed -E 's/lat="([^"]*)" lon="([^"]*)"/\1,\2/' | xcrun simctl location "${SIMULATOR_NAME}" start --speed 3.5 -

echo ""
echo "======================================================================"
echo "🎥 RECORDING ACTIVE! Storyboard Teleprompter Guide:"
echo "----------------------------------------------------------------------"
echo "⏱️  00:00 - 00:10 | Scene 1: Pan Lower Manhattan (Cold start & Fog mask)"
echo "⏱️  00:10 - 00:24 | Scene 2: Live Walk along 8th Ave (120Hz hex unlocks)"
echo "⏱️  00:24 - 00:38 | Scene 3: Tap 14th St Station (Transit sheet & headways)"
echo "⏱️  00:38 - 00:52 | Scene 4: Dismiss Sheet -> Tap Bus Capsule -> Open Journal"
echo "⏱️  00:52 - 01:04 | Scene 5: Settings -> Toggle Day/Night & Fog Opacity"
echo "⏱️  01:04 - 01:14 | Scene 6: Zoom out full NYC skyline (Outro)"
echo "======================================================================"
echo "Press [ENTER] or Ctrl+C in this terminal when finished recording."
echo "======================================================================"

cleanup() {
    trap - INT TERM EXIT
    echo ""
    echo "==> Stopping GPX playback..."
    xcrun simctl location "${SIMULATOR_NAME}" clear 2>/dev/null || true
    
    if kill -0 "${RECORD_PID}" 2>/dev/null; then
        echo "==> Finalizing video recording stream (PID: ${RECORD_PID})..."
        kill -SIGINT "${RECORD_PID}" 2>/dev/null || true
        wait "${RECORD_PID}" 2>/dev/null || true
        sleep 1
    fi

    echo "==> Resetting status bar override..."
    xcrun simctl status_bar "${SIMULATOR_NAME}" clear 2>/dev/null || true

    if [ -f "${TMP_RAW}" ] && command -v ffmpeg &>/dev/null; then
        echo "==> Optimizing video with FFmpeg to ${OUTPUT_FINAL}..."
        ffmpeg -y -i "${TMP_RAW}" \
            -c:v libx264 \
            -preset slow \
            -crf 18 \
            -pix_fmt yuv420p \
            -r 60 \
            -movflags +faststart \
            "${OUTPUT_FINAL}"
        rm -f "${TMP_RAW}"
        echo "==> ✅ Demo video successfully rendered: ${OUTPUT_FINAL}"
    elif [ -f "${TMP_RAW}" ]; then
        mv "${TMP_RAW}" "${OUTPUT_FINAL}"
        echo "==> ✅ Raw demo video saved: ${OUTPUT_FINAL}"
    fi
}

trap cleanup INT TERM EXIT

read -r _
