import fs from 'fs';
import path from 'path';
import sqlite3 from 'sqlite3';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const DeriveeCoreModule = require('../../public/wasm/derivee_core.js');

const t1Path = '/home/hatch/workspace/derivee-audits/t1/';
const walkGraphFile = path.join(t1Path, 'walk_graph.bin');
const timetableFile = path.join(t1Path, 'timetable.bin');
const ultraFile = path.join(t1Path, 'ultra_transfers.csr');
const sqliteFile = path.join(t1Path, 'transit.sqlite');

async function getStopIdByLocation(wasm, enginePtr, lat, lon) {
    const resPtr = wasm._engine_find_candidate_stops(enginePtr, lat, lon, 1000.0, 0, 1);
    if (!resPtr) throw new Error("find_candidate_stops failed");
    
    // CandidateStopResult is { stops*, count } -> 8 bytes
    const resDv = new DataView(wasm.HEAPU8.buffer, resPtr, 8);
    const stopsPtr = resDv.getUint32(0, true);
    const count = resDv.getUint32(4, true);
    
    if (count === 0) {
        wasm._engine_free_candidate_stops(resPtr);
        throw new Error(`No stops found near ${lat}, ${lon}`);
    }
    
    // CandidateStop is 30 bytes
    // uint32_t stop_id; (0)
    const stopDv = new DataView(wasm.HEAPU8.buffer, stopsPtr, 30);
    const stopId = stopDv.getUint32(0, true);
    
    wasm._engine_free_candidate_stops(resPtr);
    return stopId;
}

async function getStopNameByLatLon(db, lat, lon) {
    return new Promise((resolve, reject) => {
        db.get(`SELECT stop_name FROM stops 
                ORDER BY ((stop_lat - ?)*(stop_lat - ?) + (stop_lon - ?)*(stop_lon - ?)) ASC 
                LIMIT 1`, 
               [lat, lat, lon, lon], (err, row) => {
            if (err) reject(err);
            else if (row) resolve(row.stop_name);
            else resolve(`Unknown (${lat}, ${lon})`);
        });
    });
}

async function run() {
    console.log("Loading module...");
    const wasm = await DeriveeCoreModule();
    console.log("Module loaded.");

    const enginePtr = wasm._engine_create();

    function loadBlob(filePath, loadFn) {
        const buf = fs.readFileSync(filePath);
        const size = buf.length;
        const ptr = wasm._allocate_aligned(size, 64);
        if (ptr === 0) throw new Error("Failed to allocate aligned memory");
        
        new Uint8Array(wasm.HEAPU8.buffer, ptr, size).set(buf);
        
        const success = wasm[loadFn](enginePtr, ptr, size);
        console.log(`Loaded ${filePath}: ${success}`);
        if (!success) throw new Error(`Failed to load ${filePath}`);
    }

    loadBlob(walkGraphFile, '_engine_load_walk_graph');
    loadBlob(timetableFile, '_engine_load_timetable');
    loadBlob(ultraFile, '_engine_load_ultra');

    const db = new sqlite3.Database(sqliteFile);

    // Get coords for Times Sq and Grand Central from complexes
    const getComplexCoords = (namePart) => new Promise((resolve, reject) => {
        db.get("SELECT latitude, longitude FROM complexes WHERE complex_name LIKE ? LIMIT 1", 
               [`%${namePart}%`], (err, row) => {
            if (err) reject(err);
            else if (row) resolve(row);
            else reject(new Error(`Complex not found for ${namePart}`));
        });
    });

    const timesSq = await getComplexCoords('Times Sq');
    const grandCentral = await getComplexCoords('Barclays');

    const originStopId = await getStopIdByLocation(wasm, enginePtr, timesSq.latitude, timesSq.longitude);
    const destStopId = await getStopIdByLocation(wasm, enginePtr, grandCentral.latitude, grandCentral.longitude);

    console.log(`Origin Stop ID (internal): ${originStopId}`);
    console.log(`Dest Stop ID (internal): ${destStopId}`);

    const queryParamsPtr = wasm._malloc(16);
    const dv = new DataView(wasm.HEAPU8.buffer, queryParamsPtr, 16);
    dv.setUint32(0, originStopId, true);
    dv.setUint32(4, destStopId, true);
    
    // 8:00 AM (8 * 3600 = 28800)
    const departureTime = 28800;
    dv.setUint32(8, departureTime, true);
    dv.setUint16(12, 4, true); // max_transfers
    dv.setUint16(14, 0, true); // flags

    console.log("Computing journey...");
    const resultPtr = wasm._engine_compute_journey(enginePtr, queryParamsPtr);
    
    const resDv = new DataView(wasm.HEAPU8.buffer, resultPtr, 8);
    const segsPtr = resDv.getUint32(0, true);
    const count = resDv.getUint32(4, true);
    
    console.log(`Journey returned ${count} segments.`);
    
    if (count < 1) {
        throw new Error("No journey found!");
    }
    
    let prevExit = originStopId;
    let prevTime = departureTime;
    
    for (let i = 0; i < count; i++) {
        // Refresh views
        const segDv = new DataView(wasm.HEAPU8.buffer, segsPtr + i * 24, 24);
        const board = segDv.getUint32(0, true);
        const exit = segDv.getUint32(4, true);
        const trip = segDv.getUint32(8, true);
        const dep = segDv.getUint32(12, true);
        const arr = segDv.getUint32(16, true);
        const route = segDv.getUint16(20, true);
        
        // Fetch stop lat/lon
        const getStopInfo = async (id) => {
            const stopPtr = wasm._malloc(20); // Stop struct is 20 bytes
            wasm._engine_get_stop(enginePtr, id, stopPtr);
            const sDv = new DataView(wasm.HEAPU8.buffer, stopPtr, 20);
            const lat = sDv.getFloat32(0, true);
            const lon = sDv.getFloat32(4, true);
            wasm._free(stopPtr);
            const name = await getStopNameByLatLon(db, lat, lon);
            return name;
        };
        
        const boardName = await getStopInfo(board);
        const exitName = await getStopInfo(exit);
        
        const formatTime = (sec) => {
            const h = Math.floor(sec / 3600) % 24;
            const m = Math.floor((sec % 3600) / 60);
            return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}`;
        };
        
        const isTransfer = (trip === 0xFFFFFFFF || route === 0xFFFF);
        const mode = isTransfer ? 'Walk/Transfer' : `Route ${route} (Trip ${trip})`;
        
        console.log(`[Leg ${i+1}] ${boardName} -> ${exitName}`);
        console.log(`         Time: ${formatTime(dep)} -> ${formatTime(arr)} | ${mode}`);
        
        if (arr <= dep) throw new Error(`Leg ${i + 1}: Arrival time (${arr}) must be greater than departure time (${dep})`);
        
        if (i > 0 && board !== prevExit) {
            throw new Error(`Leg ${i + 1}: Chains broken! exit_stop of previous leg (${prevExit}) != board_stop of current leg (${board})`);
        }
        
        prevExit = exit;
        prevTime = arr;
    }
    
    const totalTime = prevTime - departureTime;
    console.log(`Total time: ${Math.round(totalTime / 60)} minutes.`);
    if (totalTime > 3 * 3600) {
        throw new Error("Total travel time > 3 hours!");
    }
    
    wasm._engine_free_result(resultPtr);
    wasm._free(queryParamsPtr);
    wasm._engine_destroy(enginePtr);
    
    const peakMem = wasm.HEAPU8.buffer.byteLength;
    console.log(`Peak WASM memory: ${(peakMem / (1024 * 1024)).toFixed(2)} MB`);
    
    db.close();
    console.log("Success!");
}

run().catch(err => {
    console.error(err);
    process.exit(1);
});
