package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"observer/internal/walk"
)

func main() {
	walkPath := flag.String("walk", "", "Path to input walk_graph.bin (required)")
	outOffsets := flag.String("out-offsets", "walk_offsets.bin", "Path to output walk_offsets.bin")
	outEdges := flag.String("out-edges", "walk_edges.bin", "Path to output walk_edges.bin")
	outRTree := flag.String("out-rtree", "walk_rtree.bin", "Path to output walk_rtree.bin")
	branching := flag.Uint("branching", 16, "R-Tree branching factor M (FlatGeobuf default = 16)")
	validate := flag.Bool("validate", true, "Validate output binaries after compilation")
	stats := flag.Bool("stats", true, "Print detailed graph and spatial index statistics")
	flag.Parse()

	if *walkPath == "" {
		flag.Usage()
		os.Exit(1)
	}

	log.Printf("[walk_csr_compiler] Loading walk graph from %s...", *walkPath)
	startTime := time.Now()

	fWalk, err := os.Open(*walkPath)
	if err != nil {
		log.Fatalf("Failed to open %s: %v", *walkPath, err)
	}
	defer fWalk.Close()

	fiWalk, err := fWalk.Stat()
	if err != nil {
		log.Fatalf("Failed to stat %s: %v", *walkPath, err)
	}

	walkView, err := walk.ReadWalkGraph(fWalk, fiWalk.Size())
	if err != nil {
		log.Fatalf("Failed to parse walk graph binary: %v", err)
	}
	log.Printf("[walk_csr_compiler] Ingested %d nodes and %d edges in %v",
		len(walkView.Nodes), len(walkView.Edges), time.Since(startTime))

	compiledGraph := &walk.CompiledWalkGraph{
		Nodes: walkView.Nodes,
		Edges: walkView.Edges,
	}

	// 1. Compile Forward CSR
	log.Printf("[walk_csr_compiler] Compiling forward CSR offsets and edges...")
	csrStart := time.Now()
	csrGraph, err := walk.CompileForwardCSR(compiledGraph)
	if err != nil {
		log.Fatalf("Failed to compile forward CSR: %v", err)
	}
	log.Printf("[walk_csr_compiler] Compiled forward CSR in %v: %d offsets, %d edges",
		time.Since(csrStart), len(csrGraph.Offsets), len(csrGraph.Edges))

	// 2. Build Packed Hilbert R-Tree
	log.Printf("[walk_csr_compiler] Constructing packed Hilbert R-Tree (M=%d)...", *branching)
	rtreeStart := time.Now()
	rtree, err := walk.BuildPackedRTree(compiledGraph.Nodes, uint32(*branching))
	if err != nil {
		log.Fatalf("Failed to construct packed R-Tree: %v", err)
	}
	log.Printf("[walk_csr_compiler] Built R-Tree in %v: %d total tree nodes (%d leaves, %d levels)",
		time.Since(rtreeStart), rtree.Metadata.TotalNodes, rtree.Metadata.NumLeaves, rtree.Metadata.NumLevels)

	// Ensure destination directory exists
	for _, p := range []string{*outOffsets, *outEdges, *outRTree} {
		dir := filepath.Dir(p)
		if dir != "." && dir != "" {
			if err := os.MkdirAll(dir, 0755); err != nil {
				log.Fatalf("Failed to create directory %s: %v", dir, err)
			}
		}
	}

	// 3. Serialize Binaries
	log.Printf("[walk_csr_compiler] Serializing %s...", *outOffsets)
	offsetsHeader, err := walk.WriteOffsetsFile(csrGraph.Offsets, *outOffsets)
	if err != nil {
		log.Fatalf("Failed to write offsets file: %v", err)
	}

	log.Printf("[walk_csr_compiler] Serializing %s...", *outEdges)
	edgesHeader, err := walk.WriteEdgesFile(csrGraph.Edges, *outEdges)
	if err != nil {
		log.Fatalf("Failed to write edges file: %v", err)
	}

	log.Printf("[walk_csr_compiler] Serializing %s...", *outRTree)
	rtreeHeader, err := walk.WriteRTreeFile(rtree, *outRTree)
	if err != nil {
		log.Fatalf("Failed to write rtree file: %v", err)
	}

	// 4. Validate output binaries if requested
	if *validate {
		log.Printf("[walk_csr_compiler] Validating generated binaries...")

		// Offsets
		fOff, err := os.Open(*outOffsets)
		if err != nil {
			log.Fatalf("Failed to open offsets for validation: %v", err)
		}
		fiOff, _ := fOff.Stat()
		readOffsets, _, err := walk.ReadOffsets(fOff, fiOff.Size())
		fOff.Close()
		if err != nil {
			log.Fatalf("Offsets validation failed: %v", err)
		}
		if len(readOffsets) != len(csrGraph.Offsets) {
			log.Fatalf("Offsets count mismatch: %d != %d", len(readOffsets), len(csrGraph.Offsets))
		}

		// Edges
		fEdg, err := os.Open(*outEdges)
		if err != nil {
			log.Fatalf("Failed to open edges for validation: %v", err)
		}
		fiEdg, _ := fEdg.Stat()
		readEdges, _, err := walk.ReadEdges(fEdg, fiEdg.Size())
		fEdg.Close()
		if err != nil {
			log.Fatalf("Edges validation failed: %v", err)
		}
		if len(readEdges) != len(csrGraph.Edges) {
			log.Fatalf("Edges count mismatch: %d != %d", len(readEdges), len(csrGraph.Edges))
		}

		// R-Tree
		fTree, err := os.Open(*outRTree)
		if err != nil {
			log.Fatalf("Failed to open rtree for validation: %v", err)
		}
		fiTree, _ := fTree.Stat()
		readTree, err := walk.ReadRTree(fTree, fiTree.Size())
		fTree.Close()
		if err != nil {
			log.Fatalf("RTree validation failed: %v", err)
		}
		if len(readTree.Nodes) != len(rtree.Nodes) {
			log.Fatalf("RTree node count mismatch: %d != %d", len(readTree.Nodes), len(rtree.Nodes))
		}

		log.Printf("[walk_csr_compiler] Validation PASSED for all 3 assets (128/232B headers, xxHash64 checksums verified)")
	}

	// 5. Print statistics if requested
	if *stats {
		fmt.Println("\n================ Walk Graph CSR & R-Tree Statistics ================")
		fmt.Printf("  Total Nodes:               %d\n", csrGraph.NumNodes)
		fmt.Printf("  Total Directed Edges:      %d\n", len(csrGraph.Edges))
		fmt.Printf("  Offsets File Size:         %.2f KB (%d bytes)\n", float64(offsetsHeader.FileSize)/1024.0, offsetsHeader.FileSize)
		fmt.Printf("  Edges File Size:           %.2f MB (%d bytes)\n", float64(edgesHeader.FileSize)/(1024.0*1024.0), edgesHeader.FileSize)
		fmt.Printf("  R-Tree Total Nodes:        %d\n", rtree.Metadata.TotalNodes)
		fmt.Printf("  R-Tree Tree Levels:        %d\n", rtree.Metadata.NumLevels)
		fmt.Printf("  R-Tree Branching Factor M: %d\n", rtree.Metadata.BranchingFactor)
		fmt.Printf("  R-Tree File Size:          %.2f MB (%d bytes)\n", float64(rtreeHeader.FileSize)/(1024.0*1024.0), rtreeHeader.FileSize)
		fmt.Printf("  Global BBox (Lat):         [%.6f, %.6f]\n", float64(rtree.Metadata.MinLatQ)*1e-7, float64(rtree.Metadata.MaxLatQ)*1e-7)
		fmt.Printf("  Global BBox (Lon):         [%.6f, %.6f]\n", float64(rtree.Metadata.MinLonQ)*1e-7, float64(rtree.Metadata.MaxLonQ)*1e-7)
		fmt.Println("=====================================================================")
	}

	log.Printf("[walk_csr_compiler] Compilation completed in %v total.", time.Since(startTime))
}
