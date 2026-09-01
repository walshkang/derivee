package walk

import (
	"math"
)

const (
	// EarthRadiusMeters is the mean Earth radius for geodesic calculations
	EarthRadiusMeters = 6371000.0
	// StandardWalkSpeedMPS is the standard assumed walking speed (1.33 m/s ~= 4.8 km/h)
	StandardWalkSpeedMPS = 1.33
	// StepsWalkSpeedMPS is the reduced walking speed across stairs (0.66 m/s)
	StepsWalkSpeedMPS = 0.66
	// ElevatorWaitPenaltyMS is the base wait and door cycle penalty for elevator usage (30s)
	ElevatorWaitPenaltyMS = 30000
)

// CompiledWalkGraph represents the flattened, CSR-indexed walk graph ready for binary serialization
type CompiledWalkGraph struct {
	Nodes []WalkNode
	Edges []WalkEdge
}

// BuildGraph constructs the CSR walk graph from extracted nodes and ways
func BuildGraph(dataset *ExtractedDataset) *CompiledWalkGraph {
	numNodes := len(dataset.Nodes)
	if numNodes == 0 {
		return &CompiledWalkGraph{
			Nodes: []WalkNode{},
			Edges: []WalkEdge{},
		}
	}

	// 1. Temporary adjacency representation: map of targetIdx -> edge for deduplication
	adj := make([]map[uint32]WalkEdge, numNodes)
	for i := range adj {
		adj[i] = make(map[uint32]WalkEdge)
	}

	// 2. Node access flags tracker
	nodeAccessFlags := make([]uint16, numNodes)
	for i, n := range dataset.Nodes {
		nodeAccessFlags[i] = n.AccessFlags
	}

	// 3. Process all extracted ways
	for _, way := range dataset.Ways {
		for i := 0; i < len(way.NodeIDs)-1; i++ {
			uOSM := way.NodeIDs[i]
			vOSM := way.NodeIDs[i+1]

			uIdx, uOk := dataset.OSMIDToNodeIdx[uOSM]
			vIdx, vOk := dataset.OSMIDToNodeIdx[vOSM]
			if !uOk || !vOk || uIdx == vIdx {
				continue
			}

			uNode := dataset.Nodes[uIdx]
			vNode := dataset.Nodes[vIdx]

			distCM := CalculateDistanceCM(uNode.LatQuantized, uNode.LonQuantized, vNode.LatQuantized, vNode.LonQuantized)
			weightMS := CalculateWeightMS(distCM, way.EdgeFlags)

			// Propagate way flags to nodes
			nodeAccessFlags[uIdx] |= uint16(way.EdgeFlags)
			nodeAccessFlags[vIdx] |= uint16(way.EdgeFlags)

			// Add u -> v edge (keeping shortest if multi-edge)
			edgeUV := WalkEdge{
				TargetNodeIdx: vIdx,
				DistanceCM:    distCM,
				WeightMS:      weightMS,
			}
			if existing, exists := adj[uIdx][vIdx]; !exists || edgeUV.WeightMS < existing.WeightMS {
				adj[uIdx][vIdx] = edgeUV
			}

			// Add v -> u edge if bidirectional
			if way.IsBidirectional {
				edgeVU := WalkEdge{
					TargetNodeIdx: uIdx,
					DistanceCM:    distCM,
					WeightMS:      weightMS,
				}
				if existing, exists := adj[vIdx][uIdx]; !exists || edgeVU.WeightMS < existing.WeightMS {
					adj[vIdx][uIdx] = edgeVU
				}
			}
		}
	}

	// 4. Flatten adjacency lists into contiguous CSR representation
	var totalEdges int
	for _, outEdges := range adj {
		totalEdges += len(outEdges)
	}

	compiledNodes := make([]WalkNode, numNodes)
	compiledEdges := make([]WalkEdge, totalEdges)

	var currentEdgeIdx uint32 = 0

	for i := 0; i < numNodes; i++ {
		outMap := adj[i]
		edgeCount := uint16(len(outMap))

		compiledNodes[i] = WalkNode{
			LatQuantized: dataset.Nodes[i].LatQuantized,
			LonQuantized: dataset.Nodes[i].LonQuantized,
			FirstEdgeIdx: currentEdgeIdx,
			EdgeCount:    edgeCount,
			AccessFlags:  nodeAccessFlags[i],
		}

		for _, edge := range outMap {
			compiledEdges[currentEdgeIdx] = edge
			currentEdgeIdx++
		}
	}

	return &CompiledWalkGraph{
		Nodes: compiledNodes,
		Edges: compiledEdges,
	}
}

// CalculateDistanceCM computes the Haversine distance in centimeters between two quantized coordinates
func CalculateDistanceCM(lat1Q, lon1Q, lat2Q, lon2Q int32) uint16 {
	lat1 := float64(lat1Q) * 1e-7 * (math.Pi / 180.0)
	lon1 := float64(lon1Q) * 1e-7 * (math.Pi / 180.0)
	lat2 := float64(lat2Q) * 1e-7 * (math.Pi / 180.0)
	lon2 := float64(lon2Q) * 1e-7 * (math.Pi / 180.0)

	dLat := lat2 - lat1
	dLon := lon2 - lon1

	sinDLat := math.Sin(dLat / 2.0)
	sinDLon := math.Sin(dLon / 2.0)

	a := sinDLat*sinDLat + math.Cos(lat1)*math.Cos(lat2)*sinDLon*sinDLon
	if a < 0 {
		a = 0
	} else if a > 1 {
		a = 1
	}

	c := 2.0 * math.Atan2(math.Sqrt(a), math.Sqrt(1.0-a))
	distMeters := EarthRadiusMeters * c

	distCM := math.Round(distMeters * 100.0)
	if distCM > float64(math.MaxUint16) {
		return math.MaxUint16
	}
	return uint16(distCM)
}

// CalculateWeightMS computes the traversal time in milliseconds given distance in cm and EdgeFlags
func CalculateWeightMS(distCM uint16, flags uint8) uint16 {
	distMeters := float64(distCM) / 100.0

	var speedMPS float64 = StandardWalkSpeedMPS
	if (flags & FlagIsSteps) != 0 {
		speedMPS = StepsWalkSpeedMPS
	}

	timeSec := distMeters / speedMPS
	timeMS := timeSec * 1000.0

	if (flags & FlagIsElevator) != 0 {
		timeMS += ElevatorWaitPenaltyMS
	}

	if timeMS > float64(math.MaxUint16) {
		return math.MaxUint16
	}
	return uint16(math.Round(timeMS))
}
