#include "RaptorEngine.hpp"
#include <emscripten.h>
#include <cstdlib>
#include <algorithm>

extern "C" {

EMSCRIPTEN_KEEPALIVE
void* allocate_aligned(size_t size, size_t alignment) {
    void* ptr = nullptr;
    if (posix_memalign(&ptr, alignment < 64 ? 64 : alignment, size) == 0) {
        return ptr;
    }
    return nullptr;
}

EMSCRIPTEN_KEEPALIVE
void* engine_create() {
    return new RaptorEngine();
}

EMSCRIPTEN_KEEPALIVE
void engine_destroy(void* engine_ptr) {
    auto* engine = static_cast<RaptorEngine*>(engine_ptr);
    delete engine;
}

EMSCRIPTEN_KEEPALIVE
bool engine_load_timetable(void* engine_ptr, uint8_t* buffer, size_t size) {
    auto* engine = static_cast<RaptorEngine*>(engine_ptr);
    return engine->load_timetable_blob(buffer, size);
}

EMSCRIPTEN_KEEPALIVE
bool engine_load_ultra(void* engine_ptr, uint8_t* buffer, size_t size) {
    auto* engine = static_cast<RaptorEngine*>(engine_ptr);
    return engine->load_ultra_blob(buffer, size);
}

EMSCRIPTEN_KEEPALIVE
bool engine_load_walk_graph(void* engine_ptr, uint8_t* buffer, size_t size) {
    auto* engine = static_cast<RaptorEngine*>(engine_ptr);
    return engine->load_walk_graph_blob(buffer, size);
}

EMSCRIPTEN_KEEPALIVE
void engine_load_bike_docks(void* engine_ptr, const BikeDock* buffer, size_t count) {
    auto* engine = static_cast<RaptorEngine*>(engine_ptr);
    engine->load_bike_docks(buffer, count);
}

EMSCRIPTEN_KEEPALIVE
void engine_update_dock_availability(void* engine_ptr, uint32_t station_id, uint16_t bikes, uint16_t ebikes, uint16_t docks) {
    auto* engine = static_cast<RaptorEngine*>(engine_ptr);
    engine->update_dock_availability(station_id, bikes, ebikes, docks);
}

struct JourneyResult {
    JourneySegment* segs;
    uint32_t count;
};

EMSCRIPTEN_KEEPALIVE
JourneyResult* engine_compute_journey(void* engine_ptr, const QueryParams* params) {
    auto* engine = static_cast<RaptorEngine*>(engine_ptr);
    auto vec = engine->compute_journey(*params);
    
    JourneyResult* result = new JourneyResult();
    result->count = vec.size();
    if (result->count > 0) {
        result->segs = new JourneySegment[result->count];
        std::copy(vec.begin(), vec.end(), result->segs);
    } else {
        result->segs = nullptr;
    }
    return result;
}

struct CandidateStopResult {
    CandidateStop* stops;
    uint32_t count;
};

EMSCRIPTEN_KEEPALIVE
void engine_get_stop(void* engine_ptr, uint32_t stop_id, Stop* out_stop) {
    auto* engine = static_cast<RaptorEngine*>(engine_ptr);
    if (out_stop) {
        *out_stop = engine->get_stop(stop_id);
    }
}

EMSCRIPTEN_KEEPALIVE
CandidateStopResult* engine_find_candidate_stops(
    void* engine_ptr,
    float lat,
    float lon,
    float max_radius,
    uint16_t flags,
    size_t max_results
) {
    auto* engine = static_cast<RaptorEngine*>(engine_ptr);
    auto vec = engine->find_candidate_stops(lat, lon, max_radius, flags, max_results);
    
    CandidateStopResult* result = new CandidateStopResult();
    result->count = vec.size();
    if (result->count > 0) {
        result->stops = new CandidateStop[result->count];
        std::copy(vec.begin(), vec.end(), result->stops);
    } else {
        result->stops = nullptr;
    }
    return result;
}

EMSCRIPTEN_KEEPALIVE
void engine_free_candidate_stops(CandidateStopResult* res) {
    if (res) {
        if (res->stops) {
            delete[] res->stops;
        }
        delete res;
    }
}

EMSCRIPTEN_KEEPALIVE
void engine_free_result(JourneyResult* res) {
    if (res) {
        if (res->segs) {
            delete[] res->segs;
        }
        delete res;
    }
}

}
