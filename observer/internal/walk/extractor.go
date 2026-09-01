package walk

import (
	"context"
	"fmt"
	"io"
	"math"
	"runtime"

	"github.com/qedus/osmpbf"
)

// BoundingBox defines an optional geographical filtering window
type BoundingBox struct {
	MinLat float64
	MinLon float64
	MaxLat float64
	MaxLon float64
}

// Contains checks if a given (lat, lon) is within the bounding box
func (b BoundingBox) Contains(lat, lon float64) bool {
	return lat >= b.MinLat && lat <= b.MaxLat && lon >= b.MinLon && lon <= b.MaxLon
}

// IsZero returns true if the bounding box has not been set
func (b BoundingBox) IsZero() bool {
	return b.MinLat == 0 && b.MinLon == 0 && b.MaxLat == 0 && b.MaxLon == 0
}

// ExtractedWay represents a walkable way segment during parsing
type ExtractedWay struct {
	OSMWayID        int64
	NodeIDs         []int64
	EdgeFlags       uint8
	IsBidirectional bool
}

// RawNode represents an ingested pedestrian node with quantized coordinates
type RawNode struct {
	OSMNodeID    int64
	LatQuantized int32
	LonQuantized int32
	AccessFlags  uint16
}

// ExtractedDataset contains raw nodes and ways extracted from OSM PBF
type ExtractedDataset struct {
	Nodes          []RawNode
	OSMIDToNodeIdx map[int64]uint32
	Ways           []ExtractedWay
}

// Extractor performs two-pass extraction of pedestrian networks from OSM PBF data
type Extractor struct {
	BBox BoundingBox
}

// NewExtractor creates a new Extractor with optional bounding box filtering
func NewExtractor(bbox BoundingBox) *Extractor {
	return &Extractor{BBox: bbox}
}

// ExtractFromSeeker runs the two-pass extraction against any io.ReadSeeker (e.g. *os.File)
func (e *Extractor) ExtractFromSeeker(ctx context.Context, seeker io.ReadSeeker) (*ExtractedDataset, error) {
	// -------------------------------------------------------------
	// PASS 1: Scan Ways to identify walkable ways and referenced Node IDs
	// -------------------------------------------------------------
	if _, err := seeker.Seek(0, io.SeekStart); err != nil {
		return nil, fmt.Errorf("failed to seek stream to beginning for Pass 1: %w", err)
	}

	decoder := osmpbf.NewDecoder(seeker)
	decoder.SetBufferSize(osmpbf.MaxBlobSize)
	if err := decoder.Start(runtime.GOMAXPROCS(0)); err != nil {
		return nil, fmt.Errorf("failed to start OSM PBF decoder for Pass 1: %w", err)
	}

	referencedNodes := make(map[int64]struct{}, 500000)
	var extractedWays []ExtractedWay
	standaloneNodeFlags := make(map[int64]uint8)

	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}

		v, err := decoder.Decode()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("error during Pass 1 decoding: %w", err)
		}

		switch obj := v.(type) {
		case *osmpbf.Way:
			eval := EvaluateWay(obj.Tags)
			if !eval.IsWalkable || len(obj.NodeIDs) < 2 {
				continue
			}

			extractedWays = append(extractedWays, ExtractedWay{
				OSMWayID:        obj.ID,
				NodeIDs:         obj.NodeIDs,
				EdgeFlags:       eval.EdgeFlags,
				IsBidirectional: eval.IsBidirectional,
			})

			for _, nid := range obj.NodeIDs {
				referencedNodes[nid] = struct{}{}
			}

		case *osmpbf.Node:
			nodeEval := EvaluateNode(obj.Tags)
			if nodeEval.IsWalkable {
				standaloneNodeFlags[obj.ID] = nodeEval.NodeFlags
				referencedNodes[obj.ID] = struct{}{}
			}
		}
	}

	// -------------------------------------------------------------
	// PASS 2: Scan Nodes to ingest referenced nodes & quantize coordinates
	// -------------------------------------------------------------
	if _, err := seeker.Seek(0, io.SeekStart); err != nil {
		return nil, fmt.Errorf("failed to seek stream to beginning for Pass 2: %w", err)
	}

	decoder2 := osmpbf.NewDecoder(seeker)
	decoder2.SetBufferSize(osmpbf.MaxBlobSize)
	if err := decoder2.Start(runtime.GOMAXPROCS(0)); err != nil {
		return nil, fmt.Errorf("failed to start OSM PBF decoder for Pass 2: %w", err)
	}

	var extractedNodes []RawNode
	osmIDToIdx := make(map[int64]uint32, len(referencedNodes))

	hasBBox := !e.BBox.IsZero()

	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}

		v, err := decoder2.Decode()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("error during Pass 2 decoding: %w", err)
		}

		if node, ok := v.(*osmpbf.Node); ok {
			if _, referenced := referencedNodes[node.ID]; !referenced {
				continue
			}

			// Bounding box filter
			if hasBBox && !e.BBox.Contains(node.Lat, node.Lon) {
				continue
			}

			latQ := int32(math.Round(node.Lat * 1e7))
			lonQ := int32(math.Round(node.Lon * 1e7))

			var accessFlags uint16 = uint16(FlagWalkable)
			if flag, exists := standaloneNodeFlags[node.ID]; exists {
				accessFlags |= uint16(flag)
			}

			idx := uint32(len(extractedNodes))
			osmIDToIdx[node.ID] = idx
			extractedNodes = append(extractedNodes, RawNode{
				OSMNodeID:    node.ID,
				LatQuantized: latQ,
				LonQuantized: lonQ,
				AccessFlags:  accessFlags,
			})
		}
	}

	// Filter ways: remove ways where referenced nodes were pruned (e.g. by bounding box)
	var validWays []ExtractedWay
	for _, way := range extractedWays {
		var validNodeIDs []int64
		for _, nid := range way.NodeIDs {
			if _, exists := osmIDToIdx[nid]; exists {
				validNodeIDs = append(validNodeIDs, nid)
			}
		}
		if len(validNodeIDs) >= 2 {
			way.NodeIDs = validNodeIDs
			validWays = append(validWays, way)
		}
	}

	return &ExtractedDataset{
		Nodes:          extractedNodes,
		OSMIDToNodeIdx: osmIDToIdx,
		Ways:           validWays,
	}, nil
}
