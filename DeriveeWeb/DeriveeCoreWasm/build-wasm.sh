#!/bin/bash
# Build the WASM routing engine with 1B-Cpp changes.
# Usage: ./build-wasm.sh
# Output: DeriveeWeb/public/wasm/derivee_core.{js,wasm}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

export PATH="$HOME/emsdk/upstream/emscripten:$HOME/emsdk/upstream/bin:$PATH"

# Derive exports from the bridge source (never hardcode)
EXPORTS=$(grep -A1 'EMSCRIPTEN_KEEPALIVE' \
  "$REPO_ROOT/DeriveeWeb/DeriveeCoreWasm/src/DeriveeWasmBridge.cpp" \
  | grep -o '[a-z_]*(' | tr -d '(' | sort -u \
  | awk 'BEGIN{printf "[\"_malloc\",\"_free\""} {printf ",\"_%s\"", $1} END{print "]"}')

em++ -std=c++20 -O3 -flto -DNDEBUG -fno-rtti -fwasm-exceptions \
  -sWASM=1 -sFILESYSTEM=0 \
  -sINITIAL_MEMORY=134217728 -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=536870912 \
  -sMALLOC="dlmalloc" \
  -sEXPORTED_FUNCTIONS="$EXPORTS" \
  -sEXPORTED_RUNTIME_METHODS='["HEAPU8","HEAP32","HEAPF32"]' \
  -sMODULARIZE=1 -sEXPORT_NAME="DeriveeCoreModule" \
  -I"$REPO_ROOT/DeriveeNative/DeriveeCore/include" \
  "$REPO_ROOT/DeriveeNative/DeriveeCore/src/RaptorEngine.cpp" \
  "$REPO_ROOT/DeriveeNative/DeriveeCore/src/BoundedAStarRouter.cpp" \
  "$REPO_ROOT/DeriveeNative/DeriveeCore/src/SubwayPositionInterpolator.cpp" \
  "$REPO_ROOT/DeriveeWeb/DeriveeCoreWasm/src/DeriveeWasmBridge.cpp" \
  -o "$REPO_ROOT/DeriveeWeb/public/wasm/derivee_core.js"

echo "WASM built: $(ls -lh "$REPO_ROOT/DeriveeWeb/public/wasm/derivee_core.wasm" | awk '{print $5}')"
