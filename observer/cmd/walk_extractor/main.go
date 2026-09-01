package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"observer/internal/walk"
)

func parseBBox(s string) (walk.BoundingBox, error) {
	if s == "" {
		return walk.BoundingBox{}, nil
	}
	parts := strings.Split(s, ",")
	if len(parts) != 4 {
		return walk.BoundingBox{}, fmt.Errorf("invalid bbox format: expected minLat,minLon,maxLat,maxLon (got %d parts)", len(parts))
	}
	minLat, err := strconv.ParseFloat(strings.TrimSpace(parts[0]), 64)
	if err != nil {
		return walk.BoundingBox{}, fmt.Errorf("invalid minLat: %w", err)
	}
	minLon, err := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
	if err != nil {
		return walk.BoundingBox{}, fmt.Errorf("invalid minLon: %w", err)
	}
	maxLat, err := strconv.ParseFloat(strings.TrimSpace(parts[2]), 64)
	if err != nil {
		return walk.BoundingBox{}, fmt.Errorf("invalid maxLat: %w", err)
	}
	maxLon, err := strconv.ParseFloat(strings.TrimSpace(parts[3]), 64)
	if err != nil {
		return walk.BoundingBox{}, fmt.Errorf("invalid maxLon: %w", err)
	}
	return walk.BoundingBox{
		MinLat: minLat,
		MinLon: minLon,
		MaxLat: maxLat,
		MaxLon: maxLon,
	}, nil
}

func main() {
	pbfPath := flag.String("pbf", "", "Path to input .osm.pbf file (required)")
	outPath := flag.String("out", "walk_graph.bin", "Path to output walk_graph.bin file")
	bboxStr := flag.String("bbox", "", "Optional bounding box: minLat,minLon,maxLat,maxLon")
	validate := flag.Bool("validate", true, "Validate output binary after compilation")
	stats := flag.Bool("stats", true, "Print detailed graph statistics")
	flag.Parse()

	if *pbfPath == "" {
		flag.Usage()
		os.Exit(1)
	}

	bbox, err := parseBBox(*bboxStr)
	if err != nil {
		log.Fatalf("Error parsing bbox: %v", err)
	}

	log.Printf("[walk_extractor] Opening OSM PBF: %s", *pbfPath)
	pbfFile, err := os.Open(*pbfPath)
	if err != nil {
		log.Fatalf("Failed to open PBF file %s: %v", *pbfPath, err)
	}
	defer pbfFile.Close()

	startTime := time.Now()
	extractor := walk.NewExtractor(bbox)

	log.Printf("[walk_extractor] Starting two-pass OSM PBF extraction...")
	dataset, err := extractor.ExtractFromSeeker(context.Background(), pbfFile)
	if err != nil {
		log.Fatalf("Extraction failed: %v", err)
	}

	extractDuration := time.Since(startTime)
	log.Printf("[walk_extractor] Pass 1 & Pass 2 complete in %v: ingested %d nodes and %d ways",
		extractDuration, len(dataset.Nodes), len(dataset.Ways))

	// Build CSR topology
	log.Printf("[walk_extractor] Assembling adjacency graph and flattening CSR layout...")
	buildStart := time.Now()
	graph := walk.BuildGraph(dataset)
	log.Printf("[walk_extractor] Graph compiled in %v: %d nodes, %d directed edges",
		time.Since(buildStart), len(graph.Nodes), len(graph.Edges))

	// Serialize binary
	log.Printf("[walk_extractor] Serializing binary walk graph to %s...", *outPath)
	header, err := walk.WriteWalkGraphFile(graph, *outPath)
	if err != nil {
		log.Fatalf("Failed to write walk graph binary: %v", err)
	}

	log.Printf("[walk_extractor] Wrote %d bytes (Checksum XXH64: 0x%016X)", header.FileSize, header.ChecksumXXH64)

	// Validate output
	if *validate {
		log.Printf("[walk_extractor] Validating binary file integrity...")
		statResults, err := walk.ValidateBinaryFile(*outPath)
		if err != nil {
			log.Fatalf("Binary validation failed: %v", err)
		}
		log.Printf("[walk_extractor] Validation PASSED (128B header, page-aligned TOC, xxHash64 checksum verified)")

		if *stats {
			fmt.Println("\n================ Walk Graph Statistics ================")
			fmt.Printf("  Total Nodes:               %d\n", statResults.TotalNodes)
			fmt.Printf("  Total Directed Edges:      %d\n", statResults.TotalEdges)
			fmt.Printf("  Total Network Length:      %.2f km\n", statResults.TotalLengthMeters/1000.0)
			fmt.Printf("  Avg / Max Outdegree:       %.2f / %d\n", statResults.AvgOutDegree, statResults.MaxOutDegree)
			fmt.Printf("  Wheelchair Accessible:     %d (%.1f%%)\n", statResults.WheelchairAccessibleNodes, statResults.WheelchairRatio*100.0)
			fmt.Printf("  Stairs / Steps Nodes:      %d\n", statResults.StepsCount)
			fmt.Printf("  Elevators / Vertical:      %d\n", statResults.ElevatorCount)
			fmt.Printf("  Binary File Size:          %.2f MB (%d bytes)\n", float64(statResults.FileSize)/(1024*1024), statResults.FileSize)
			fmt.Printf("  Checksum (XXH64):          0x%016X\n", statResults.ChecksumXXH64)
			fmt.Println("=======================================================")
		}
	}

	log.Printf("[walk_extractor] Successfully compiled walk graph in %v total.", time.Since(startTime))
}
