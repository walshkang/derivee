package ultra

import (
	"observer/internal/walk"
)

// DijkstraEngine executes bounded SSSP sweeps over the pedestrian graph using Bitmasked Dial's Queue
type DijkstraEngine struct {
	State           []NodeState // Contiguous interleaved array of size |V| (8 bytes per node)
	WheelchairFlags []uint8     // Accessibility bitmask per node sized to |V|
	Queue           *DialQueue  // Circular bucket priority queue (B=1024)
	CurrentGen      uint32      // Generation counter for O(1) resets
	numNodes        int32
	candidateGen    []uint32    // Generation-stamped direct lookup for candidate deduplication (zero allocs)
	candidateIdx    []int32     // Position in candidate slice
}

// NewDijkstraEngine allocates the flat, zero-alloc state buffers for Dijkstra traversal
func NewDijkstraEngine(numNodes int32) *DijkstraEngine {
	engine := &DijkstraEngine{
		State:           make([]NodeState, numNodes),
		WheelchairFlags: make([]uint8, numNodes),
		Queue:           NewDialQueue(numNodes),
		CurrentGen:      1,
		numNodes:        numNodes,
		candidateGen:    make([]uint32, 2048),
		candidateIdx:    make([]int32, 2048),
	}

	for i := range engine.State {
		engine.State[i].Gen = 0
		engine.State[i].Dist = InfDist
	}

	return engine
}

// EnsureCandidateCapacity grows the internal candidate lookup buffer if required
func (e *DijkstraEngine) EnsureCandidateCapacity(minStops int) {
	if len(e.candidateGen) < minStops {
		newCap := minStops * 2
		newGen := make([]uint32, newCap)
		newIdx := make([]int32, newCap)
		copy(newGen, e.candidateGen)
		copy(newIdx, e.candidateIdx)
		e.candidateGen = newGen
		e.candidateIdx = newIdx
	}
}

// Reset increments the generation counter, providing an O(1) state reset with overflow protection
func (e *DijkstraEngine) Reset() {
	e.CurrentGen++
	if e.CurrentGen == 0 { // uint32 overflow protection
		for i := range e.State {
			e.State[i].Gen = 0
			e.State[i].Dist = InfDist
			e.WheelchairFlags[i] = 0
		}
		for i := range e.candidateGen {
			e.candidateGen[i] = 0
			e.candidateIdx[i] = 0
		}
		e.CurrentGen = 1
	}
	e.Queue.Reset()
}

// GetDist returns the tentative distance of node for the current search generation
func (e *DijkstraEngine) GetDist(node int32) uint32 {
	if node < 0 || node >= e.numNodes || e.State[node].Gen != e.CurrentGen {
		return InfDist
	}
	return e.State[node].Dist
}

// SetDist updates the tentative distance and generation of a node
func (e *DijkstraEngine) SetDist(node int32, d uint32, isWheelchair bool) {
	e.State[node].Gen = e.CurrentGen
	e.State[node].Dist = d
	if isWheelchair {
		e.WheelchairFlags[node] = FlagWheelchairAccessible
	} else {
		e.WheelchairFlags[node] = 0
	}
}

// FindCandidateTransfers runs a bounded Dijkstra search from startNode and discovers candidate transfers.
// Guaranteed 0 dynamic heap allocations when candidateBuffer has sufficient capacity.
func (e *DijkstraEngine) FindCandidateTransfers(
	nodes []walk.WalkNode,
	edges []walk.WalkEdge,
	startNode int32,
	originStopIdx uint32,
	initialTimeSec uint16,
	tauMaxSec uint32,
	walkNodeToStops [][]SnappedStop,
	candidateBuffer []TransferCandidate,
) []TransferCandidate {
	if startNode < 0 || startNode >= e.numNodes {
		return candidateBuffer[:0]
	}

	e.Reset()
	candidates := candidateBuffer[:0]

	// Initialize start node
	initDist := uint32(initialTimeSec)
	e.SetDist(startNode, initDist, true)
	e.Queue.PushOrRelax(startNode, InfDist, initDist)

	for e.Queue.Len() > 0 {
		u := e.Queue.PopMin(e.State, e.CurrentGen)
		if u == NilNode {
			break
		}

		dU := e.GetDist(u)
		if dU > tauMaxSec {
			break
		}

		uWheelchair := e.WheelchairFlags[u] == FlagWheelchairAccessible

		// Check if any transit stops are associated with node u
		if int(u) < len(walkNodeToStops) {
			for _, snapped := range walkNodeToStops[u] {
				if snapped.StopIndex == originStopIdx {
					continue // Skip self loop
				}

				totalDuration := dU + uint32(snapped.TimeSec)
				if totalDuration <= tauMaxSec {
					dur16 := uint16(totalDuration)
					flags := uint8(0)
					if uWheelchair && snapped.IsWheelchair {
						flags |= FlagWheelchairAccessible
					}

					stopID := snapped.StopIndex
					if int(stopID) >= len(e.candidateGen) {
						e.EnsureCandidateCapacity(int(stopID) + 1)
					}

					// Zero-allocation O(1) candidate deduplication via generation stamps
					if e.candidateGen[stopID] == e.CurrentGen {
						idx := e.candidateIdx[stopID]
						if dur16 < candidates[idx].Duration {
							candidates[idx].Duration = dur16
							candidates[idx].Flags = flags
						}
					} else {
						e.candidateGen[stopID] = e.CurrentGen
						e.candidateIdx[stopID] = int32(len(candidates))
						candidates = append(candidates, TransferCandidate{
							TargetStop: stopID,
							Duration:   dur16,
							Flags:      flags,
						})
					}
				}
			}
		}

		// Expand outgoing edges of node u
		uNode := nodes[u]
		firstEdge := uNode.FirstEdgeIdx
		lastEdge := firstEdge + uint32(uNode.EdgeCount)

		for edgeIdx := firstEdge; edgeIdx < lastEdge && edgeIdx < uint32(len(edges)); edgeIdx++ {
			edge := edges[edgeIdx]
			v := int32(edge.TargetNodeIdx)
			if v < 0 || v >= e.numNodes {
				continue
			}

			// Convert edge cost from milliseconds to seconds (minimum 1s)
			weightSec := uint32((edge.WeightMS + 999) / 1000)
			if weightSec == 0 {
				weightSec = 1
			}

			newDist := dU + weightSec
			if newDist <= tauMaxSec {
				oldDist := e.GetDist(v)
				if newDist < oldDist {
					// Check step-free accessibility across edge
					edgeWheelchair := (uNode.AccessFlags & uint16(walk.FlagWheelchairAccessible)) != 0
					vWheelchair := uWheelchair && edgeWheelchair

					e.SetDist(v, newDist, vWheelchair)
					e.Queue.PushOrRelax(v, oldDist, newDist)
				}
			}
		}
	}

	return candidates
}

// FindCandidateTransfersCSR runs a bounded Dijkstra search directly over forward CSR offsets and edges.
// Eliminates WalkNode coordinate loads during edge expansion, maximizing CPU L1 cache throughput.
// Guaranteed 0 dynamic heap allocations when candidateBuffer has sufficient capacity.
func (e *DijkstraEngine) FindCandidateTransfersCSR(
	offsets []uint32,
	edges []walk.WalkEdge,
	accessFlags []uint16,
	startNode int32,
	originStopIdx uint32,
	initialTimeSec uint16,
	tauMaxSec uint32,
	walkNodeToStops [][]SnappedStop,
	candidateBuffer []TransferCandidate,
) []TransferCandidate {
	if startNode < 0 || startNode >= e.numNodes || int(startNode+1) >= len(offsets) {
		return candidateBuffer[:0]
	}

	e.Reset()
	candidates := candidateBuffer[:0]

	initDist := uint32(initialTimeSec)
	e.SetDist(startNode, initDist, true)
	e.Queue.PushOrRelax(startNode, InfDist, initDist)

	for e.Queue.Len() > 0 {
		u := e.Queue.PopMin(e.State, e.CurrentGen)
		if u == NilNode {
			break
		}

		dU := e.GetDist(u)
		if dU > tauMaxSec {
			break
		}

		uWheelchair := e.WheelchairFlags[u] == FlagWheelchairAccessible

		// Check snapped transit stops at node u
		if int(u) < len(walkNodeToStops) {
			for _, snapped := range walkNodeToStops[u] {
				if snapped.StopIndex == originStopIdx {
					continue
				}

				totalDuration := dU + uint32(snapped.TimeSec)
				if totalDuration <= tauMaxSec {
					dur16 := uint16(totalDuration)
					flags := uint8(0)
					if uWheelchair && snapped.IsWheelchair {
						flags |= FlagWheelchairAccessible
					}

					stopID := snapped.StopIndex
					if int(stopID) >= len(e.candidateGen) {
						e.EnsureCandidateCapacity(int(stopID) + 1)
					}

					if e.candidateGen[stopID] == e.CurrentGen {
						idx := e.candidateIdx[stopID]
						if dur16 < candidates[idx].Duration {
							candidates[idx].Duration = dur16
							candidates[idx].Flags = flags
						}
					} else {
						e.candidateGen[stopID] = e.CurrentGen
						e.candidateIdx[stopID] = int32(len(candidates))
						candidates = append(candidates, TransferCandidate{
							TargetStop: stopID,
							Duration:   dur16,
							Flags:      flags,
						})
					}
				}
			}
		}

		// Expand outgoing edges using CSR offsets without loading node coordinate structs
		firstEdge := offsets[u]
		lastEdge := offsets[u+1]

		uWheelchairAccess := true
		if int(u) < len(accessFlags) {
			uWheelchairAccess = (accessFlags[u] & uint16(walk.FlagWheelchairAccessible)) != 0
		}

		for edgeIdx := firstEdge; edgeIdx < lastEdge && edgeIdx < uint32(len(edges)); edgeIdx++ {
			edge := edges[edgeIdx]
			v := int32(edge.TargetNodeIdx)
			if v < 0 || v >= e.numNodes {
				continue
			}

			weightSec := uint32((edge.WeightMS + 999) / 1000)
			if weightSec == 0 {
				weightSec = 1
			}

			newDist := dU + weightSec
			if newDist <= tauMaxSec {
				oldDist := e.GetDist(v)
				if newDist < oldDist {
					vWheelchair := uWheelchair && uWheelchairAccess
					e.SetDist(v, newDist, vWheelchair)
					e.Queue.PushOrRelax(v, oldDist, newDist)
				}
			}
		}
	}

	return candidates
}
