package walk

import (
	"fmt"
	"os"
)

// GraphStatistics reports summary metrics about a validated walk graph
type GraphStatistics struct {
	TotalNodes                int
	TotalEdges                int
	TotalLengthMeters         float64
	WheelchairAccessibleNodes int
	WheelchairRatio           float64
	StepsCount                int
	ElevatorCount             int
	MaxOutDegree              uint16
	AvgOutDegree              float64
	FileSize                  int64
	ChecksumXXH64             uint64
}

// ValidateGraphStructure validates topological consistency and index bounds of a CompiledWalkGraph
func ValidateGraphStructure(graph *CompiledWalkGraph) error {
	if err := ValidateLayout(); err != nil {
		return fmt.Errorf("layout validation failed: %w", err)
	}

	numNodes := uint32(len(graph.Nodes))
	numEdges := uint32(len(graph.Edges))

	for i, node := range graph.Nodes {
		// Verify coordinate bounds
		if node.LatQuantized < -900000000 || node.LatQuantized > 900000000 {
			return fmt.Errorf("node %d latitude out of range: %d", i, node.LatQuantized)
		}
		if node.LonQuantized < -1800000000 || node.LonQuantized > 1800000000 {
			return fmt.Errorf("node %d longitude out of range: %d", i, node.LonQuantized)
		}

		// Verify CSR edge offset bounds
		endEdge := node.FirstEdgeIdx + uint32(node.EdgeCount)
		if endEdge > numEdges {
			return fmt.Errorf("node %d edge range [%d, %d) exceeds total edges %d", i, node.FirstEdgeIdx, endEdge, numEdges)
		}
	}

	for i, edge := range graph.Edges {
		if edge.TargetNodeIdx >= numNodes {
			return fmt.Errorf("edge %d target index %d >= total nodes %d", i, edge.TargetNodeIdx, numNodes)
		}
	}

	return nil
}

// ValidateBinaryFile inspects a compiled walk_graph.bin file and produces statistics
func ValidateBinaryFile(path string) (*GraphStatistics, error) {
	fileInfo, err := os.Stat(path)
	if err != nil {
		return nil, fmt.Errorf("failed to stat file %s: %w", path, err)
	}

	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("failed to open file %s: %w", path, err)
	}
	defer f.Close()

	view, err := ReadWalkGraph(f, fileInfo.Size())
	if err != nil {
		return nil, fmt.Errorf("binary verification failed: %w", err)
	}

	graph := &CompiledWalkGraph{
		Nodes: view.Nodes,
		Edges: view.Edges,
	}

	if err := ValidateGraphStructure(graph); err != nil {
		return nil, fmt.Errorf("topological validation failed: %w", err)
	}

	// Compute statistics
	var totalLengthCM uint64
	var wheelchairNodes int
	var maxDegree uint16
	var totalSteps int
	var totalElevators int

	for _, n := range view.Nodes {
		if (n.AccessFlags & uint16(FlagWheelchairAccessible)) != 0 {
			wheelchairNodes++
		}
		if (n.AccessFlags & uint16(FlagIsSteps)) != 0 {
			totalSteps++
		}
		if (n.AccessFlags & uint16(FlagIsElevator)) != 0 {
			totalElevators++
		}
		if n.EdgeCount > maxDegree {
			maxDegree = n.EdgeCount
		}
	}

	for _, e := range view.Edges {
		totalLengthCM += uint64(e.DistanceCM)
	}

	var avgDegree float64
	var wcRatio float64
	if len(view.Nodes) > 0 {
		avgDegree = float64(len(view.Edges)) / float64(len(view.Nodes))
		wcRatio = float64(wheelchairNodes) / float64(len(view.Nodes))
	}

	return &GraphStatistics{
		TotalNodes:                len(view.Nodes),
		TotalEdges:                len(view.Edges),
		TotalLengthMeters:         float64(totalLengthCM) / 100.0,
		WheelchairAccessibleNodes: wheelchairNodes,
		WheelchairRatio:           wcRatio,
		StepsCount:                totalSteps,
		ElevatorCount:             totalElevators,
		MaxOutDegree:              maxDegree,
		AvgOutDegree:              avgDegree,
		FileSize:                  fileInfo.Size(),
		ChecksumXXH64:             view.Header.ChecksumXXH64,
	}, nil
}
