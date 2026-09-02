package walk

import (
	"math"
)

// SearchBBox searches the packed R-tree for all node indices whose bounding box intersects [qMinLat, qMinLon, qMaxLat, qMaxLon].
// Executes with ZERO heap allocations when resultBuffer has sufficient capacity.
func (tree *RTreeIndex) SearchBBox(qMinLat, qMinLon, qMaxLat, qMaxLon int32, resultBuffer []uint32) []uint32 {
	if len(tree.Nodes) == 0 {
		return resultBuffer
	}

	// Fixed-capacity call-stack buffer for tree traversal (depth <= 16 for branching factor 16)
	var stack [64]uint32
	stackPtr := 0

	// Push Root node (index 0)
	stack[stackPtr] = 0
	stackPtr++

	for stackPtr > 0 {
		stackPtr--
		currIdx := stack[stackPtr]
		node := tree.Nodes[currIdx]

		// Bounding box intersection test
		if node.MinLatQ > qMaxLat || node.MaxLatQ < qMinLat ||
			node.MinLonQ > qMaxLon || node.MaxLonQ < qMinLon {
			continue
		}

		if node.Flags&RTreeFlagLeaf != 0 {
			// Leaf node: ChildOffset holds the original graph NodeIdx
			resultBuffer = append(resultBuffer, node.ChildOffset)
			continue
		}

		// Internal node: inspect children
		numChildren := uint32(node.NumChildren)
		firstChild := node.ChildOffset

		for i := uint32(0); i < numChildren; i++ {
			childIdx := firstChild + i
			if childIdx < uint32(len(tree.Nodes)) {
				c := tree.Nodes[childIdx]
				if !(c.MinLatQ > qMaxLat || c.MaxLatQ < qMinLat ||
					c.MinLonQ > qMaxLon || c.MaxLonQ < qMinLon) {
					if stackPtr < len(stack) {
						stack[stackPtr] = childIdx
						stackPtr++
					}
				}
			}
		}
	}

	return resultBuffer
}

// MinBoxDistCM calculates the minimum distance in centimeters from a point to an axis-aligned bounding box
func MinBoxDistCM(latQ, lonQ, minLat, minLon, maxLat, maxLon int32) uint32 {
	cLat := latQ
	if cLat < minLat {
		cLat = minLat
	} else if cLat > maxLat {
		cLat = maxLat
	}

	cLon := lonQ
	if cLon < minLon {
		cLon = minLon
	} else if cLon > maxLon {
		cLon = maxLon
	}

	return uint32(CalculateDistanceCM(latQ, lonQ, cLat, cLon))
}

// FindNearest finds the closest walk node to (latQ, lonQ) within maxDistMeters.
// Returns (nodeIdx, distCM, found). Executes with ZERO dynamic heap allocations.
func (tree *RTreeIndex) FindNearest(latQ, lonQ int32, maxDistMeters float64) (uint32, uint16, bool) {
	if len(tree.Nodes) == 0 {
		return 0, 0, false
	}

	maxDistCM := uint32(math.Round(maxDistMeters * 100.0))
	if maxDistCM > uint32(math.MaxUint16) {
		maxDistCM = uint32(math.MaxUint16)
	}

	bestDistCM := maxDistCM
	var bestNode uint32 = 0
	found := false

	// Fixed call-stack traversal buffer
	var stack [64]uint32
	stackPtr := 0

	// Push Root node
	stack[stackPtr] = 0
	stackPtr++

	for stackPtr > 0 {
		stackPtr--
		currIdx := stack[stackPtr]
		node := tree.Nodes[currIdx]

		// Prune if minimum distance to box exceeds current best
		boxDist := MinBoxDistCM(latQ, lonQ, node.MinLatQ, node.MinLonQ, node.MaxLatQ, node.MaxLonQ)
		if boxDist > bestDistCM {
			continue
		}

		if node.Flags&RTreeFlagLeaf != 0 {
			pointDist := uint32(CalculateDistanceCM(latQ, lonQ, node.MinLatQ, node.MinLonQ))
			if pointDist <= bestDistCM {
				bestDistCM = pointDist
				bestNode = node.ChildOffset
				found = true
			}
			continue
		}

		// Internal node: examine children
		numChildren := uint32(node.NumChildren)
		firstChild := node.ChildOffset

		for i := uint32(0); i < numChildren; i++ {
			childIdx := firstChild + i
			if childIdx < uint32(len(tree.Nodes)) {
				c := tree.Nodes[childIdx]
				cDist := MinBoxDistCM(latQ, lonQ, c.MinLatQ, c.MinLonQ, c.MaxLatQ, c.MaxLonQ)
				if cDist <= bestDistCM {
					if stackPtr < len(stack) {
						stack[stackPtr] = childIdx
						stackPtr++
					}
				}
			}
		}
	}

	return bestNode, uint16(bestDistCM), found
}

// FindWithinRadius finds all walk nodes within radiusMeters of (latQ, lonQ) using R-tree filtering
func (tree *RTreeIndex) FindWithinRadius(latQ, lonQ int32, radiusMeters float64, resultBuffer []uint32) []uint32 {
	if len(tree.Nodes) == 0 || radiusMeters <= 0 {
		return resultBuffer
	}

	latRad := float64(latQ) * 1e-7 * (math.Pi / 180.0)
	cosLat := math.Cos(latRad)
	if cosLat < 0.01 {
		cosLat = 0.01
	}

	degLat := (radiusMeters / 111320.0)
	degLon := (radiusMeters / (111320.0 * cosLat))

	dLatQ := int32(math.Ceil(degLat * 1e7))
	dLonQ := int32(math.Ceil(degLon * 1e7))

	qMinLat := latQ - dLatQ
	qMaxLat := latQ + dLatQ
	qMinLon := lonQ - dLonQ
	qMaxLon := lonQ + dLonQ

	// Temporary candidate buffer on stack for spatial filtering
	var candidateBuf [512]uint32
	candidates := tree.SearchBBox(qMinLat, qMinLon, qMaxLat, qMaxLon, candidateBuf[:0])

	maxCM := uint32(math.Round(radiusMeters * 100.0))

	for _, nodeIdx := range candidates {
		// Calculate point distance (coordinates from leaf in tree)
		// For accurate distance filtering
		distCM := uint32(tree.distanceToNode(nodeIdx, latQ, lonQ))
		if distCM <= maxCM {
			resultBuffer = append(resultBuffer, nodeIdx)
		}
	}

	return resultBuffer
}

func (tree *RTreeIndex) distanceToNode(targetNodeIdx uint32, latQ, lonQ int32) uint16 {
	// Find the leaf entry in tree
	// Leaves are stored at the end of the flattened node array
	numLeaves := tree.Metadata.NumLeaves
	totalNodes := uint32(len(tree.Nodes))
	if numLeaves == 0 || totalNodes < numLeaves {
		return math.MaxUint16
	}

	leafBase := totalNodes - numLeaves
	// In leaf level, search or lookup
	for i := leafBase; i < totalNodes; i++ {
		if tree.Nodes[i].ChildOffset == targetNodeIdx {
			return CalculateDistanceCM(latQ, lonQ, tree.Nodes[i].MinLatQ, tree.Nodes[i].MinLonQ)
		}
	}
	return math.MaxUint16
}
