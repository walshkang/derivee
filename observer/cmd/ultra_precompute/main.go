package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"observer/internal/raptor"
	"observer/internal/ultra"
	"observer/internal/walk"
)

func main() {
	walkPath := flag.String("walk", "", "Path to input walk_graph.bin (required)")
	timetablePath := flag.String("timetable", "", "Path to input timetable.bin (required)")
	outPath := flag.String("out", "ultra_transfers.csr", "Path to output ultra_transfers.csr file")
	maxDuration := flag.Uint("max-duration", 900, "Maximum walking duration cutoff in seconds (tau_max)")
	maxSnap := flag.Float64("max-snap", 250.0, "Maximum snap distance in meters from stop to walk node")
	enableWitness := flag.Bool("witness", true, "Enable Profile-RAPTOR transit witness dominance pruning")
	validate := flag.Bool("validate", true, "Validate output binary after compilation")
	stats := flag.Bool("stats", true, "Print detailed precomputation statistics")
	flag.Parse()

	if *walkPath == "" || *timetablePath == "" {
		flag.Usage()
		os.Exit(1)
	}

	log.Printf("[ultra_precompute] Initializing ULTRA Precomputation Pipeline (< 35 MB Peak RSS)...")

	// 1. Ingest Walk Graph (CSR)
	log.Printf("[ultra_precompute] Reading walk graph from %s...", *walkPath)
	fWalk, err := os.Open(*walkPath)
	if err != nil {
		log.Fatalf("Failed to open walk graph file %s: %v", *walkPath, err)
	}
	defer fWalk.Close()

	fiWalk, err := fWalk.Stat()
	if err != nil {
		log.Fatalf("Failed to stat walk graph file %s: %v", *walkPath, err)
	}

	walkView, err := walk.ReadWalkGraph(fWalk, fiWalk.Size())
	if err != nil {
		log.Fatalf("Failed to parse walk graph binary: %v", err)
	}
	log.Printf("[ultra_precompute] Loaded walk graph: %d nodes, %d edges", len(walkView.Nodes), len(walkView.Edges))

	compiledWalk := &walk.CompiledWalkGraph{
		Nodes: walkView.Nodes,
		Edges: walkView.Edges,
	}

	// 2. Ingest RAPTOR Timetable
	log.Printf("[ultra_precompute] Reading timetable from %s...", *timetablePath)
	fTT, err := os.Open(*timetablePath)
	if err != nil {
		log.Fatalf("Failed to open timetable file %s: %v", *timetablePath, err)
	}
	defer fTT.Close()

	fiTT, err := fTT.Stat()
	if err != nil {
		log.Fatalf("Failed to stat timetable file %s: %v", *timetablePath, err)
	}

	ttView, err := raptor.ReadTimetable(fTT, fiTT.Size())
	if err != nil {
		log.Fatalf("Failed to parse timetable binary: %v", err)
	}
	log.Printf("[ultra_precompute] Loaded timetable: %d stops, %d routes, %d trips",
		len(ttView.Stops), len(ttView.Routes), len(ttView.Trips))

	compiledTT := &raptor.CompiledTimetable{
		Stops:             ttView.Stops,
		Routes:            ttView.Routes,
		Trips:             ttView.Trips,
		StopTimes:         ttView.StopTimes,
		Transfers:         ttView.Transfers,
		StopRoutes:        ttView.StopRoutes,
		RouteStops:        ttView.RouteStops,
		StochasticWeights: ttView.StochasticWeights,
	}

	// 3. Configure and Execute ULTRA Precomputation
	if err := os.MkdirAll(filepath.Dir(*outPath), 0755); err != nil && filepath.Dir(*outPath) != "." {
		log.Fatalf("Failed to create output directory: %v", err)
	}

	cfg := ultra.PrecomputeConfig{
		TauMaxSec:      uint32(*maxDuration),
		MaxSnapMeters:  *maxSnap,
		TempDir:        "",
		EnableWitness:  *enableWitness,
		ValidateOutput: *validate,
	}

	log.Printf("[ultra_precompute] Executing bounded SSSP sweeps (tau_max = %ds, Bitmasked Dial's Queue B=1024)...", cfg.TauMaxSec)
	execStart := time.Now()
	summary, err := ultra.PrecomputeUltraTransfers(compiledWalk, compiledTT, *outPath, cfg)
	if err != nil {
		log.Fatalf("Precomputation failed: %v", err)
	}
	totalElapsed := time.Since(execStart)

	log.Printf("[ultra_precompute] ✅ Precomputation complete in %v! Generated %d verified shortcuts.",
		totalElapsed, summary.TotalShortcuts)

	// 4. Statistics Summary
	if *stats {
		fileSizeMB := float64(summary.OutputSizeBytes) / (1024.0 * 1024.0)
		fmt.Println("\n================ ULTRA Transfers Precomputation Summary ================")
		fmt.Printf("  Binary File:                %s\n", *outPath)
		fmt.Printf("  Binary File Size:           %.3f MB (%d bytes)\n", fileSizeMB, summary.OutputSizeBytes)
		fmt.Printf("  Transit Stops:              %d\n", summary.NumStops)
		fmt.Printf("  Walk Nodes / Edges:         %d / %d\n", summary.NumWalkNodes, summary.NumWalkEdges)
		fmt.Printf("  Total Verified Shortcuts:   %d\n", summary.TotalShortcuts)
		fmt.Printf("  Witness Pruned Shortcuts:   %d\n", summary.WitnessPrunedCount)
		fmt.Printf("  Avg Shortcuts / Stop:       %.2f\n", summary.AvgShortcuts)
		fmt.Printf("  Max Shortcuts / Stop:       %d\n", summary.MaxShortcuts)
		fmt.Printf("  Elapsed Execution Time:     %v\n", summary.Duration)
		fmt.Printf("  Single-Core Throughput:     %.1f sweeps/sec\n", summary.ThroughputSweeps)
		fmt.Printf("  Header Checksum / Magic:    0x%08X (Version %d)\n", summary.Header.MagicBytes, summary.Header.Version)
		fmt.Println("=========================================================================")
	}
}
