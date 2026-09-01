package ultra

import (
	"testing"
)

func TestDialQueueBasicPushPop(t *testing.T) {
	numNodes := int32(10)
	dq := NewDialQueue(numNodes)

	state := make([]NodeState, numNodes)
	currentGen := uint32(1)

	// Insert nodes with distances
	nodes := []struct {
		id   int32
		dist uint32
	}{
		{id: 0, dist: 50},
		{id: 1, dist: 10},
		{id: 2, dist: 30},
		{id: 3, dist: 5},
		{id: 4, dist: 100},
	}

	for _, n := range nodes {
		state[n.id] = NodeState{Dist: n.dist, Gen: currentGen}
		dq.PushOrRelax(n.id, InfDist, n.dist)
	}

	if dq.Len() != 5 {
		t.Fatalf("expected len 5, got %d", dq.Len())
	}

	expectedOrder := []int32{3, 1, 2, 0, 4} // sorted by dist: 5, 10, 30, 50, 100
	for i, exp := range expectedOrder {
		minNode := dq.PopMin(state, currentGen)
		if minNode != exp {
			t.Errorf("step %d: expected node %d, got %d", i, exp, minNode)
		}
	}

	if dq.Len() != 0 {
		t.Errorf("expected empty queue, got len %d", dq.Len())
	}
}

func TestDialQueueRelaxationDecreaseKey(t *testing.T) {
	numNodes := int32(5)
	dq := NewDialQueue(numNodes)
	state := make([]NodeState, numNodes)
	currentGen := uint32(1)

	state[0] = NodeState{Dist: 100, Gen: currentGen}
	dq.PushOrRelax(0, InfDist, 100)

	state[1] = NodeState{Dist: 200, Gen: currentGen}
	dq.PushOrRelax(1, InfDist, 200)

	// Decrease key for node 1 from 200 to 50
	dq.PushOrRelax(1, 200, 50)
	state[1].Dist = 50

	if dq.Len() != 2 {
		t.Fatalf("expected len 2, got %d", dq.Len())
	}

	// Node 1 should pop first now (dist 50 < dist 100)
	first := dq.PopMin(state, currentGen)
	if first != 1 {
		t.Errorf("expected node 1 first, got %d", first)
	}

	second := dq.PopMin(state, currentGen)
	if second != 0 {
		t.Errorf("expected node 0 second, got %d", second)
	}
}

func TestDialQueueCircularWrapAround(t *testing.T) {
	numNodes := int32(5)
	dq := NewDialQueue(numNodes)
	state := make([]NodeState, numNodes)
	currentGen := uint32(1)

	// Insert distances larger than BucketSize (1024)
	dists := []uint32{1025, 1500, 2048, 3000}
	for i, d := range dists {
		node := int32(i)
		state[node] = NodeState{Dist: d, Gen: currentGen}
		dq.PushOrRelax(node, InfDist, d)
	}

	expectedOrder := []int32{0, 1, 2, 3}
	for i, exp := range expectedOrder {
		minNode := dq.PopMin(state, currentGen)
		if minNode != exp {
			t.Errorf("step %d: expected node %d, got %d", i, exp, minNode)
		}
	}
}

func TestDialQueueStaleGenerationEviction(t *testing.T) {
	numNodes := int32(5)
	dq := NewDialQueue(numNodes)
	state := make([]NodeState, numNodes)

	// Insert with generation 1
	state[0] = NodeState{Dist: 10, Gen: 1}
	dq.PushOrRelax(0, InfDist, 10)

	// Pop with generation 2 (node 0 should be skipped as stale)
	popped := dq.PopMin(state, 2)
	if popped != NilNode {
		t.Errorf("expected NilNode for stale generation, got %d", popped)
	}
}
