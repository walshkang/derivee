#!/bin/bash
set -e

# Setup emsdk
source /home/hatch/workspace/emsdk/emsdk_env.sh

# Target directory
mkdir -p /home/hatch/workspace/derivee/DeriveeWeb/public/wasm

echo "Compiling without -flto..."
em++ \
  -std=c++20 \
  -O3 \
  -DNDEBUG \
  -fno-rtti \
  -fwasm-exceptions \
  -sWASM=1 \
  -sFILESYSTEM=0 \
  -sINITIAL_MEMORY=134217728 \
  -sALLOW_MEMORY_GROWTH=1 \
  -sMAXIMUM_MEMORY=536870912 \
  -sMALLOC="dlmalloc" \
  -sEXPORTED_FUNCTIONS='["_malloc","_free","_allocate_aligned","_engine_create","_engine_destroy","_engine_load_timetable","_engine_load_ultra","_engine_load_walk_graph","_engine_compute_journey","_engine_get_stop","_engine_find_candidate_stops","_engine_free_candidate_stops","_engine_free_result"]' \
  -sEXPORTED_RUNTIME_METHODS='["HEAPU8", "HEAP32", "HEAPF32"]' \
  -sMODULARIZE=1 \
  -sEXPORT_NAME="DeriveeCoreModule" \
  -I/home/hatch/workspace/derivee/DeriveeNative/DeriveeCore/include \
  /home/hatch/workspace/derivee/DeriveeNative/DeriveeCore/src/RaptorEngine.cpp \
  /home/hatch/workspace/derivee/DeriveeNative/DeriveeCore/src/BoundedAStarRouter.cpp \
  /home/hatch/workspace/derivee/DeriveeNative/DeriveeCore/src/SubwayPositionInterpolator.cpp \
  /home/hatch/workspace/derivee/DeriveeWeb/DeriveeCoreWasm/src/DeriveeWasmBridge.cpp \
  -o /home/hatch/workspace/derivee/DeriveeWeb/public/wasm/derivee_core.js

echo "Compilation successful"
