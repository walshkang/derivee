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

# 2. Terminate Stale App Process, Reset Explored Hexes DB, Set Appearance & Launch Fresh
echo "==> [2/4] Resetting explored hexes DB, Day Mode, pristine status bar, Columbus Circle fix..."
xcrun simctl terminate "${SIMULATOR_NAME}" com.derivee.Derivee 2>/dev/null || true

CONTAINER_DATA=$(xcrun simctl get_app_container "${SIMULATOR_NAME}" com.derivee.Derivee data 2>/dev/null || true)
if [ -n "${CONTAINER_DATA}" ] && [ -d "${CONTAINER_DATA}" ]; then
    DB_PATH="${CONTAINER_DATA}/Library/Application Support/derivee_spatial.sqlite"
    if [ -f "${DB_PATH}" ]; then
        echo "    🧹 Cleared previously explored hexes & POIs from SQLite"
        sqlite3 "${DB_PATH}" "DELETE FROM explored_hexes; DELETE FROM discovered_pois; VACUUM;" 2>/dev/null || rm -f "${CONTAINER_DATA}/Library/Application Support/derivee_spatial.sqlite"*
    fi
fi

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

# 4. Start Waypoint Walk from GPX (Walks 5 hexes / ~260m over ~20s, then holds position)
echo "==> [4/4] Starting 5-hex GPX walk (~20s duration, will stop and hold position)..."
grep -o 'lat="[^"]*" lon="[^"]*"' "${GPX_PATH}" | head -n 15 | sed -E 's/lat="([^"]*)" lon="([^"]*)"/\1,\2/' | xcrun simctl location "${SIMULATOR_NAME}" start --speed 13 -

echo ""
echo "======================================================================"
echo "🎥 RECORDING ACTIVE!"
echo "----------------------------------------------------------------------"
echo "🚶 1. Real-Time Walk: The blue dot will walk 5 hexes (~18 seconds) and stop."
echo "👆 2. Manual Demo: After it stops, interact at your own pace:"
echo "      - Tap 59th St Station -> View Multi-Route Badges, Live Arrivals & Full Timetable tab"
echo "      - Tap Bus Capsule (preview stops) -> Tap top-right Profile FAB -> Stats & Milestones"
echo "      - Tap Gear icon -> Toggle Day/Night & drag Fog Opacity slider -> Dismiss back to map"
echo "      - Zoom out -> Full clamped NYC skyline overview (~5km rubber-band margin)"
echo "🛑 3. Finish: Press [ENTER] or Ctrl+C in this terminal to render video."
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
