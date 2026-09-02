package walk

import (
	"sort"
)

// NormalizeCoordinates maps integer quantized coordinates (latQ, lonQ) within a bounding box
// to a uniform integer grid [0, maxVal]
func NormalizeCoordinates(latQ, lonQ, minLat, minLon, maxLat, maxLon int32, maxVal uint32) (uint32, uint32) {
	if maxLat <= minLat {
		maxLat = minLat + 1
	}
	if maxLon <= minLon {
		maxLon = minLon + 1
	}

	latRange := int64(maxLat - minLat)
	lonRange := int64(maxLon - minLon)

	latOffset := int64(latQ - minLat)
	if latOffset < 0 {
		latOffset = 0
	} else if latOffset > latRange {
		latOffset = latRange
	}

	lonOffset := int64(lonQ - minLon)
	if lonOffset < 0 {
		lonOffset = 0
	} else if lonOffset > lonRange {
		lonOffset = lonRange
	}

	normY := uint32((latOffset * int64(maxVal)) / latRange)
	normX := uint32((lonOffset * int64(maxVal)) / lonRange)

	return normX, normY
}

// EncodeHilbert2D computes the 1D Hilbert index for integer coordinates (x, y) in a (2^bits x 2^bits) grid.
// bits specifies the order of the Hilbert curve (typically 16 for 16-bit per dimension -> 32-bit distance).
func EncodeHilbert2D(x, y uint32, bits uint32) uint64 {
	var d uint64 = 0
	var s uint32 = 1 << (bits - 1)

	for s > 0 {
		var rx uint32 = 0
		if (x & s) > 0 {
			rx = 1
		}
		var ry uint32 = 0
		if (y & s) > 0 {
			ry = 1
		}

		d += uint64(s) * uint64(s) * uint64((3*rx)^ry)

		// Rotate / flip quadrant
		if ry == 0 {
			if rx == 1 {
				x = s - 1 - x
				y = s - 1 - y
			}
			x, y = y, x
		}

		s >>= 1
	}

	return d
}

// HilbertSortItem encapsulates spatial position and Hilbert curve value for a walk node
type HilbertSortItem struct {
	OriginalIndex uint32
	HilbertVal    uint64
	LatQ          int32
	LonQ          int32
}

// SortNodesByHilbert computes Hilbert curve distances and returns items sorted by Hilbert order
func SortNodesByHilbert(nodes []WalkNode, minLat, minLon, maxLat, maxLon int32) []HilbertSortItem {
	items := make([]HilbertSortItem, len(nodes))
	if len(nodes) == 0 {
		return items
	}

	const hilbertBits = 16
	const maxCoord = (1 << hilbertBits) - 1

	for i, n := range nodes {
		normX, normY := NormalizeCoordinates(n.LatQuantized, n.LonQuantized, minLat, minLon, maxLat, maxLon, maxCoord)
		hVal := EncodeHilbert2D(normX, normY, hilbertBits)
		items[i] = HilbertSortItem{
			OriginalIndex: uint32(i),
			HilbertVal:    hVal,
			LatQ:          n.LatQuantized,
			LonQ:          n.LonQuantized,
		}
	}

	sort.Slice(items, func(i, j int) bool {
		if items[i].HilbertVal == items[j].HilbertVal {
			return items[i].OriginalIndex < items[j].OriginalIndex
		}
		return items[i].HilbertVal < items[j].HilbertVal
	})

	return items
}
