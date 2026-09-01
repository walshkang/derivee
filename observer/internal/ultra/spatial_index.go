package ultra

import (
	"math"

	"observer/internal/walk"
)

const (
	// DefaultMaxSnapDistanceMeters is the maximum search radius when snapping a transit stop to the walk network
	DefaultMaxSnapDistanceMeters = 250.0
	// GridCellSizeDeg is the approximate bounding box cell size in degrees (~250m at mid-latitudes)
	GridCellSizeDeg = 0.0025
	// GridCellSizeQuantized is GridCellSizeDeg * 1e7
	GridCellSizeQuantized int32 = 25000
)

// GridKey encodes a 2D integer cell coordinate for spatial grid hashing
type GridKey struct {
	X int32
	Y int32
}

// SpatialIndex provides fast nearest-node lookups and builds the inverted walkNode -> []SnappedStop index
type SpatialIndex struct {
	grid       map[GridKey][]int32 // Maps grid cell -> slice of WalkNode indices
	numNodes   int32
	nodes      []walk.WalkNode
}

// BuildSpatialIndex indexes all walkable nodes into a 2D uniform grid
func BuildSpatialIndex(nodes []walk.WalkNode) *SpatialIndex {
	si := &SpatialIndex{
		grid:     make(map[GridKey][]int32, len(nodes)/4),
		numNodes: int32(len(nodes)),
		nodes:    nodes,
	}

	for i, n := range nodes {
		gx := n.LonQuantized / GridCellSizeQuantized
		gy := n.LatQuantized / GridCellSizeQuantized
		key := GridKey{X: gx, Y: gy}
		si.grid[key] = append(si.grid[key], int32(i))
	}

	return si
}

// FindNearestWalkNode finds the closest walkable node within maxDistMeters to (latQ, lonQ)
func (si *SpatialIndex) FindNearestWalkNode(latQ, lonQ int32, maxDistMeters float64) (int32, uint16) {
	if si.numNodes == 0 {
		return NilNode, 0
	}

	maxDistCM := uint32(math.Round(maxDistMeters * 100.0))
	if maxDistCM > uint32(math.MaxUint16) {
		maxDistCM = uint32(math.MaxUint16)
	}

	centerGX := lonQ / GridCellSizeQuantized
	centerGY := latQ / GridCellSizeQuantized

	bestNode := NilNode
	bestDistCM := uint32(math.MaxUint32)

	// Search 3x3 surrounding cells
	for dx := int32(-1); dx <= 1; dx++ {
		for dy := int32(-1); dy <= 1; dy++ {
			key := GridKey{X: centerGX + dx, Y: centerGY + dy}
			candidates, found := si.grid[key]
			if !found {
				continue
			}

			for _, nodeIdx := range candidates {
				n := si.nodes[nodeIdx]
				distCM := uint32(walk.CalculateDistanceCM(latQ, lonQ, n.LatQuantized, n.LonQuantized))
				if distCM <= maxDistCM && distCM < bestDistCM {
					bestDistCM = distCM
					bestNode = nodeIdx
				}
			}
		}
	}

	if bestNode == NilNode {
		return NilNode, 0
	}
	return bestNode, uint16(bestDistCM)
}

// StopLocation encapsulates coordinates for snapping transit stops to the walk graph
type StopLocation struct {
	StopIndex uint32
	Lat       float64
	Lon       float64
}

// MapStopsToWalkGraph snaps all transit stops to the walk graph and builds the walkNodeToStops index
// Returns:
// 1. stopToWalkNode: array of size |S| mapping stopIndex -> snapped walkNodeIdx (or NilNode)
// 2. walkNodeToStops: array of size |V| mapping walkNodeIdx -> slice of SnappedStop
func (si *SpatialIndex) MapStopsToWalkGraph(
	stops []StopLocation,
	maxSnapMeters float64,
) ([]int32, [][]SnappedStop) {
	numStops := len(stops)
	stopToWalkNode := make([]int32, numStops)
	walkNodeToStops := make([][]SnappedStop, si.numNodes)

	for _, s := range stops {
		latQ := int32(math.Round(s.Lat * 1e7))
		lonQ := int32(math.Round(s.Lon * 1e7))

		nearestNode, distCM := si.FindNearestWalkNode(latQ, lonQ, maxSnapMeters)
		stopToWalkNode[s.StopIndex] = nearestNode

		if nearestNode != NilNode {
			timeMS := walk.CalculateWeightMS(distCM, walk.FlagWalkable)
			timeSec := uint16((timeMS + 999) / 1000) // Ceiling division to seconds

			walkNodeToStops[nearestNode] = append(walkNodeToStops[nearestNode], SnappedStop{
				StopIndex:    s.StopIndex,
				DistanceCM:   distCM,
				TimeSec:      timeSec,
				IsWheelchair: true, // Standard pedestrian snap links are assumed step-free
			})
		}
	}

	return stopToWalkNode, walkNodeToStops
}
