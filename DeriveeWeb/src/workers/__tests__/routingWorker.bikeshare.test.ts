import test from 'node:test';
import assert from 'node:assert';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);
const DeriveeCoreModule = require('../../../public/wasm/derivee_core.js');

const t1Path = '/home/hatch/workspace/derivee-audits/t1/';
const walkGraphFile = path.join(t1Path, 'walk_graph.bin');
const timetableFile = path.join(t1Path, 'timetable.bin');
const ultraFile = path.join(t1Path, 'ultra_transfers.csr');

function loadBlob(wasm, enginePtr, filePath, loadFn) {
    const buf = fs.readFileSync(filePath);
    const size = buf.length;
    const ptr = wasm._allocate_aligned(size, 64);
    if (ptr === 0) throw new Error("Failed to allocate aligned memory");
    new Uint8Array(wasm.HEAPU8.buffer, ptr, size).set(buf);
    const success = wasm[loadFn](enginePtr, ptr, size);
    if (!success) throw new Error(`Failed to load ${filePath}`);
}

function getStopIdByLocation(wasm, enginePtr, lat, lon) {
    const resPtr = wasm._engine_find_candidate_stops(enginePtr, lat, lon, 1000.0, 0, 1);
    if (!resPtr) throw new Error("find_candidate_stops failed");
    
    const resDv = new DataView(wasm.HEAPU8.buffer, resPtr, 8);
    const stopsPtr = resDv.getUint32(0, true);
    const count = resDv.getUint32(4, true);
    
    if (count === 0) {
        wasm._engine_free_candidate_stops(resPtr);
        throw new Error(`No stops found near ${lat}, ${lon}`);
    }
    
    const stopDv = new DataView(wasm.HEAPU8.buffer, stopsPtr, 30);
    const stopId = stopDv.getUint32(0, true);
    
    wasm._engine_free_candidate_stops(resPtr);
    return stopId;
}

test('Bike-share: Load GBFS fixture and compute route', async () => {
    const wasm = await DeriveeCoreModule();
    const enginePtr = wasm._engine_create();

    loadBlob(wasm, enginePtr, walkGraphFile, '_engine_load_walk_graph');
    loadBlob(wasm, enginePtr, timetableFile, '_engine_load_timetable');
    loadBlob(wasm, enginePtr, ultraFile, '_engine_load_ultra');

    // We'll just grab the first and fifth stop in the timetable
    const originStopId = 1;
    const destStopId = 5;
    
    const stopPtr = wasm._malloc(20);
    wasm._engine_get_stop(enginePtr, originStopId, stopPtr);
    let sDv = new DataView(wasm.HEAPU8.buffer, stopPtr, 20);
    const originLat = sDv.getFloat32(0, true);
    const originLon = sDv.getFloat32(4, true);

    wasm._engine_get_stop(enginePtr, destStopId, stopPtr);
    sDv = new DataView(wasm.HEAPU8.buffer, stopPtr, 20);
    const destLat = sDv.getFloat32(0, true);
    const destLon = sDv.getFloat32(4, true);
    wasm._free(stopPtr);

    const docksBufferPtr = wasm._malloc(2 * 20);
    const dv = new DataView(wasm.HEAPU8.buffer, docksBufferPtr, 2 * 20);

    // Dock 1: near origin stop
    dv.setUint32(0, 1001, true);
    dv.setFloat32(4, originLat, true);
    dv.setFloat32(8, originLon, true);
    dv.setUint16(12, 5, true); // bikes
    dv.setUint16(14, 0, true); // ebikes
    dv.setUint16(16, 5, true); // docks
    dv.setUint16(18, 0, true);

    // Dock 2: near dest stop
    dv.setUint32(20, 1002, true);
    dv.setFloat32(24, destLat, true);
    dv.setFloat32(28, destLon, true);
    dv.setUint16(32, 5, true);
    dv.setUint16(34, 0, true);
    dv.setUint16(36, 5, true);
    dv.setUint16(38, 0, true);

    wasm._engine_load_bike_docks(enginePtr, docksBufferPtr, 2);

    const queryParamsPtr = wasm._malloc(16);
    const qDv = new DataView(wasm.HEAPU8.buffer, queryParamsPtr, 16);
    qDv.setUint32(0, originStopId, true);
    qDv.setUint32(4, destStopId, true);
    qDv.setUint32(8, 28800, true); // 8:00 AM
    qDv.setUint16(12, 4, true); // max_transfers
    qDv.setUint16(14, 0, true); // flags

    const resultPtr = wasm._engine_compute_journey(enginePtr, queryParamsPtr);
    const resDv = new DataView(wasm.HEAPU8.buffer, resultPtr, 8);
    const count = resDv.getUint32(4, true);

    assert.ok(count > 0, "Expected a journey to be found");

    wasm._engine_free_result(resultPtr);

    // Negative case: 0 bikes at origin, should still pass via transit but slower?
    // Wait, let's explicitly test just the e-bike vs classic bike speed.
    // E-bike
    dv.setUint16(14, 5, true); // ebikes available
    wasm._engine_update_dock_availability(enginePtr, 1001, 5, 5, 5);
    
    const resultEbikePtr = wasm._engine_compute_journey(enginePtr, queryParamsPtr);
    const resEbikeDv = new DataView(wasm.HEAPU8.buffer, resultEbikePtr, 8);
    const ebikeCount = resEbikeDv.getUint32(4, true);
    assert.ok(ebikeCount > 0, "Expected a journey to be found with e-bikes");
    
    // Extract arrival time for e-bike
    const ebikeSegsPtr = resEbikeDv.getUint32(0, true);
    const lastSegEbike = new DataView(wasm.HEAPU8.buffer, ebikeSegsPtr + (ebikeCount - 1) * 24, 24);
    const arrEbike = lastSegEbike.getUint32(16, true);
    wasm._engine_free_result(resultEbikePtr);

    // Classic bike
    wasm._engine_update_dock_availability(enginePtr, 1001, 5, 0, 5);
    const resultClassicPtr = wasm._engine_compute_journey(enginePtr, queryParamsPtr);
    const resClassicDv = new DataView(wasm.HEAPU8.buffer, resultClassicPtr, 8);
    const classicCount = resClassicDv.getUint32(4, true);
    assert.ok(classicCount > 0, "Expected a journey to be found with classic bikes");
    
    const classicSegsPtr = resClassicDv.getUint32(0, true);
    const lastSegClassic = new DataView(wasm.HEAPU8.buffer, classicSegsPtr + (classicCount - 1) * 24, 24);
    const arrClassic = lastSegClassic.getUint32(16, true);
    wasm._engine_free_result(resultClassicPtr);

    console.log("Ebike Segments:");
    for (let i = 0; i < ebikeCount; i++) {
        const seg = new DataView(wasm.HEAPU8.buffer, ebikeSegsPtr + i * 24, 24);
        console.log(`trip: ${seg.getUint32(8, true)}, arr: ${seg.getUint32(16, true)}`);
    }
    console.log("Classic Segments:");
    for (let i = 0; i < classicCount; i++) {
        const seg = new DataView(wasm.HEAPU8.buffer, classicSegsPtr + i * 24, 24);
        console.log(`trip: ${seg.getUint32(8, true)}, arr: ${seg.getUint32(16, true)}`);
    }
    assert.ok(arrEbike < arrClassic, `E-bike arrival (${arrEbike}) should be strictly faster than classic bike (${arrClassic})`);

    // Negative case: 0 bikes at origin
    wasm._engine_update_dock_availability(enginePtr, 1001, 0, 0, 5);
    const resultNoBikesPtr = wasm._engine_compute_journey(enginePtr, queryParamsPtr);
    const resNoBikesDv = new DataView(wasm.HEAPU8.buffer, resultNoBikesPtr, 8);
    const noBikesCount = resNoBikesDv.getUint32(4, true);
    
    if (noBikesCount > 0) {
        const noBikesSegsPtr = resNoBikesDv.getUint32(0, true);
        const lastSegNoBikes = new DataView(wasm.HEAPU8.buffer, noBikesSegsPtr + (noBikesCount - 1) * 24, 24);
        const arrNoBikes = lastSegNoBikes.getUint32(16, true);
        assert.ok(arrNoBikes >= arrClassic, "Route without bikes should be slower or equal to classic");
    }

    // Negative case: 0 docks at destination
    wasm._engine_update_dock_availability(enginePtr, 1001, 5, 0, 5);
    wasm._engine_update_dock_availability(enginePtr, 1002, 5, 0, 0); // 0 docks
    const resultNoDocksPtr = wasm._engine_compute_journey(enginePtr, queryParamsPtr);
    const resNoDocksDv = new DataView(wasm.HEAPU8.buffer, resultNoDocksPtr, 8);
    const noDocksCount = resNoDocksDv.getUint32(4, true);
    
    if (noDocksCount > 0) {
        const noDocksSegsPtr = resNoDocksDv.getUint32(0, true);
        const lastSegNoDocks = new DataView(wasm.HEAPU8.buffer, noDocksSegsPtr + (noDocksCount - 1) * 24, 24);
        const arrNoDocks = lastSegNoDocks.getUint32(16, true);
        assert.ok(arrNoDocks >= arrClassic, "Route without destination docks should be slower or equal to classic");
    }

    wasm._free(queryParamsPtr);
    wasm._free(docksBufferPtr);
    wasm._engine_destroy(enginePtr);
});
