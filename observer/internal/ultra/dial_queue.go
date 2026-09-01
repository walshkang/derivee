package ultra

// DialQueue implements a circular bucket priority queue with B=1024 buckets.
// Modulo is computed via single-cycle bitwise masking (dist & 1023).
// Linked list pointers are maintained in flat contiguous slices to guarantee zero heap allocations.
type DialQueue struct {
	buckets     [BucketSize]int32 // Head node indices for each bucket
	next        []int32           // Doubly-linked list next pointers sized to |V|
	prev        []int32           // Doubly-linked list prev pointers sized to |V|
	minBucket   int32             // Monotonic / circular cursor tracking lowest non-empty bucket
	numElements int32
}

// NewDialQueue creates and initializes a DialQueue pre-allocated for numNodes
func NewDialQueue(numNodes int32) *DialQueue {
	dq := &DialQueue{
		next: make([]int32, numNodes),
		prev: make([]int32, numNodes),
	}
	dq.Reset()
	return dq
}

// Reset clears all buckets and linked list pointers in O(BucketSize) time
func (dq *DialQueue) Reset() {
	for i := 0; i < BucketSize; i++ {
		dq.buckets[i] = NilNode
	}
	dq.minBucket = 0
	dq.numElements = 0
}

// Unlink removes a node from its current bucket doubly-linked list
func (dq *DialQueue) Unlink(node int32, b uint32) {
	p := dq.prev[node]
	n := dq.next[node]

	if p != NilNode {
		dq.next[p] = n
	} else {
		dq.buckets[b] = n
	}

	if n != NilNode {
		dq.prev[n] = p
	}

	dq.next[node] = NilNode
	dq.prev[node] = NilNode
}

// PushOrRelax inserts or updates a node's position in the circular bucket queue
func (dq *DialQueue) PushOrRelax(node int32, oldDist, newDist uint32) {
	if oldDist != InfDist {
		dq.Unlink(node, oldDist&BucketMask)
		dq.numElements--
	}

	b := newDist & BucketMask
	head := dq.buckets[b]

	dq.next[node] = head
	dq.prev[node] = NilNode
	if head != NilNode {
		dq.prev[head] = node
	}
	dq.buckets[b] = node

	if dq.numElements == 0 || int32(newDist) < dq.minBucket {
		dq.minBucket = int32(newDist)
	}
	dq.numElements++
}

// PopMin retrieves the node with the minimum tentative distance, advancing minBucket as necessary
func (dq *DialQueue) PopMin(distSlice []NodeState, currentGen uint32) int32 {
	if dq.numElements == 0 {
		return NilNode
	}

	for dq.numElements > 0 {
		idx := uint32(dq.minBucket) & BucketMask
		head := dq.buckets[idx]

		if head != NilNode {
			// Stale entry eviction from previous search generation
			if distSlice[head].Gen != currentGen {
				dq.Unlink(head, idx)
				dq.numElements--
				continue
			}

			// Verify distance matches current monotonic cursor
			if distSlice[head].Dist == uint32(dq.minBucket) {
				dq.Unlink(head, idx)
				dq.numElements--
				return head
			}

			// If head.Dist > minBucket, it belongs to a future lap of the circular queue
		}

		dq.minBucket++
	}

	return NilNode
}

// Len returns the number of active elements in the queue
func (dq *DialQueue) Len() int32 {
	return dq.numElements
}
