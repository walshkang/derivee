package ultra

import (
	"fmt"
	"math"
	"sort"
	"time"

	"observer/internal/raptor"
	"observer/internal/walk"
)

// PrecomputeConfig specifies configuration parameters for the precomputation engine
type PrecomputeConfig struct {
	TauMaxSec             uint32
	MaxSnapMeters         float64
	MaxBusBusTransferMeters float64
	TempDir               string
	EnableWitness         bool
	ValidateOutput        bool
}

// DefaultPrecomputeConfig returns default configuration parameters for OCI E2.1.Micro
func DefaultPrecomputeConfig() PrecomputeConfig {
	return PrecomputeConfig{
		TauMaxSec:             DefaultTauMaxSec,
		MaxSnapMeters:         DefaultMaxSnapDistanceMeters,
		MaxBusBusTransferMeters: 150.0,
		TempDir:               "",
		EnableWitness:         true,
		ValidateOutput:        true,
	}
}

// PrecomputeStats records throughput and graph statistics from a precomputation run
type PrecomputeStats struct {
	NumStops          uint32
	NumWalkNodes      uint32
	NumWalkEdges      uint32
	TotalShortcuts    uint64
	AvgShortcuts      float64
	MaxShortcuts      uint32
	Duration          time.Duration
	ThroughputSweeps  float64
	Header            BinaryHeader
	OutputSizeBytes   int64
	WitnessPrunedCount uint64
}

// PrecomputeUltraTransfers executes the two-phase ULTRA precomputation pipeline
func PrecomputeUltraTransfers(
	walkGraph *walk.CompiledWalkGraph,
	timetable *raptor.CompiledTimetable,
	outputPath string,
	cfg PrecomputeConfig,
) (*PrecomputeStats, error) {
	startTime := time.Now()

	numStops := uint32(len(timetable.Stops))
	numNodes := int32(len(walkGraph.Nodes))

	if numStops == 0 {
		return nil, fmt.Errorf("cannot precompute ULTRA transfers: timetable contains 0 stops")
	}

	// 1. Build Spatial Index & Snap Stops
	stopLocations := make([]StopLocation, numStops)
	for i, s := range timetable.Stops {
		stopLocations[i] = StopLocation{
			StopIndex: uint32(i),
			Lat:       float64(s.Latitude),
			Lon:       float64(s.Longitude),
		}
	}

	spatialIndex := BuildSpatialIndex(walkGraph.Nodes)
	stopToWalkNode, walkNodeToStops := spatialIndex.MapStopsToWalkGraph(stopLocations, cfg.MaxSnapMeters)

	// 2. Initialize Single-Core Zero-Alloc SSSP Engine & Spool Writer
	dijkstraEngine := NewDijkstraEngine(numNodes)
	spoolWriter, err := NewSpoolWriter(cfg.TempDir, numStops, cfg.TauMaxSec)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize spool writer: %w", err)
	}
	defer spoolWriter.Close()

	// 3. Initialize Witness Pruning Engine
	var witnessEngine *WitnessEngine
	var compactTT *CompactTimetable
	if cfg.EnableWitness {
		witnessEngine = NewWitnessEngine(numStops)
		compactTT = BuildCompactTimetable(timetable)
	}

	candidateBuf := make([]TransferCandidate, 0, 512)
	var maxShortcuts uint32 = 0
	var totalWitnessPruned uint64 = 0

	// 4. Sequential Stop-by-Stop Sweep (< 35 MB Active RSS)
	for u := uint32(0); u < numStops; u++ {
		startNode := stopToWalkNode[u]
		if startNode == NilNode {
			// Unsnapped stop has 0 outgoing shortcuts
			if err := spoolWriter.AppendStopShortcuts(u, nil); err != nil {
				return nil, err
			}
			continue
		}

		// Phase A: Bounded SSSP via Bitmasked Dial's Queue
		candidates := dijkstraEngine.FindCandidateTransfers(
			walkGraph.Nodes,
			walkGraph.Edges,
			startNode,
			u,
			0,
			cfg.TauMaxSec,
			walkNodeToStops,
			candidateBuf,
		)

		initialCandidateCount := len(candidates)

		// Phase B: Batched Profile-RAPTOR Witness Pruning
		if cfg.EnableWitness && witnessEngine != nil && len(candidates) > 0 {
			candidates = witnessEngine.PruneShortcutsWithWitnesses(u, candidates, compactTT, timetable)
			totalWitnessPruned += uint64(initialCandidateCount - len(candidates))
		}

		// Phase B2: Bus-bus transfer pruning (1B-Go)
		// Nobody transfers bus->bus across 8 blocks mid-trip. Cap bus-bus
		// footpaths at MaxBusBusTransferMeters (150m). Subway-subway and
		// bus-subway keep the standard radius.
		if raptor.IsBusStop(timetable.Stops[u]) {
			filtered := candidates[:0]
			for _, c := range candidates {
				if raptor.IsBusStop(timetable.Stops[c.TargetStop]) {
					// Both bus stops: check distance
					distM := haversineMeters(
						float64(timetable.Stops[u].Latitude),
						float64(timetable.Stops[u].Longitude),
						float64(timetable.Stops[c.TargetStop].Latitude),
						float64(timetable.Stops[c.TargetStop].Longitude),
					)
					if distM > cfg.MaxBusBusTransferMeters {
						continue
					}
				}
				filtered = append(filtered, c)
			}
			candidates = filtered
		}

		// Sort surviving shortcuts by target_stop ascending for deterministic CSR ordering
		if len(candidates) > 1 {
			sort.Slice(candidates, func(i, j int) bool {
				return candidates[i].TargetStop < candidates[j].TargetStop
			})
		}

		if uint32(len(candidates)) > maxShortcuts {
			maxShortcuts = uint32(len(candidates))
		}

		if err := spoolWriter.AppendStopShortcuts(u, candidates); err != nil {
			return nil, err
		}
	}

	// 5. Final Pass: Sequential File Stitching
	header, err := spoolWriter.StitchToFile(outputPath)
	if err != nil {
		return nil, fmt.Errorf("failed to stitch ultra_transfers.csr: %w", err)
	}

	elapsed := time.Since(startTime)
	throughput := float64(numStops) / elapsed.Seconds()
	avgShortcuts := 0.0
	if numStops > 0 {
		avgShortcuts = float64(header.NumShortcuts) / float64(numStops)
	}

	// Calculate output binary size
	outputSize := int64(HeaderSize) + int64(numStops+1)*8 + int64(header.NumShortcuts)*7

	stats := &PrecomputeStats{
		NumStops:           numStops,
		NumWalkNodes:       uint32(numNodes),
		NumWalkEdges:       uint32(len(walkGraph.Edges)),
		TotalShortcuts:     header.NumShortcuts,
		AvgShortcuts:       avgShortcuts,
		MaxShortcuts:       maxShortcuts,
		Duration:           elapsed,
		ThroughputSweeps:   throughput,
		Header:             *header,
		OutputSizeBytes:    outputSize,
		WitnessPrunedCount: totalWitnessPruned,
	}

	// 6. Optional Validation
	if cfg.ValidateOutput {
		if err := ValidateUltraCSRFile(outputPath); err != nil {
			return nil, fmt.Errorf("validation failed for %s: %w", outputPath, err)
		}
	}

	return stats, nil
}

// haversineMeters returns the great-circle distance in meters between two
// lat/lon points (degrees).
func haversineMeters(lat1, lon1, lat2, lon2 float64) float64 {
	const earthRadiusM = 6371000.0
	const degToRad = 0.017453292519943295

	dLat := (lat2 - lat1) * degToRad
	dLon := (lon2 - lon1) * degToRad
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*degToRad)*math.Cos(lat2*degToRad)*
			math.Sin(dLon/2)*math.Sin(dLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return earthRadiusM * c
}
