package gtfs

import (
	"fmt"
	"sort"
	"strings"
)

// ColorConsolidationThreshold defines the maximum color distance for consolidating
// routes into a single trunk ribbon (INV-CORR-01: delta E <= 2.0).
const ColorConsolidationThreshold = 2.0

// ColorDistance computes perceptual or exact color difference between two hex color strings.
type ColorDistance interface {
	Distance(hex1, hex2 string) float64
}

// ExactHexDistance implements ColorDistance using case-insensitive hex string equality.
// Returns 0.0 if identical, 100.0 otherwise.
type ExactHexDistance struct{}

// Distance evaluates exact hex equality after stripping whitespace and leading '#'
func (e ExactHexDistance) Distance(hex1, hex2 string) float64 {
	h1 := strings.ToUpper(strings.TrimPrefix(strings.TrimSpace(hex1), "#"))
	h2 := strings.ToUpper(strings.TrimPrefix(strings.TrimSpace(hex2), "#"))
	if h1 != "" && h1 == h2 {
		return 0.0
	}
	return 100.0
}

// DefaultColorDistance provides the default ExactHexDistance implementation
var DefaultColorDistance ColorDistance = ExactHexDistance{}

// TrunkBundle represents a consolidated color ribbon within a corridor.
type TrunkBundle struct {
	BundleIndex  int      `json:"bundle_index"`  // 0 <= BundleIndex < BundleSize
	BundleSize   int      `json:"bundle_size"`   // Number of ribbons in this corridor (K <= 3)
	TrunkColor   string   `json:"trunk_color"`   // Canonical hex color string
	RouteIDs     []string `json:"route_ids"`     // Routes consolidated into this ribbon
	RouteNames   []string `json:"routes"`        // Route short names consolidated
	CompositeKey string   `json:"composite_key"` // e.g. "badge_4_5_6"
	ModalClass   int      `json:"modal_class"`   // 0=Subway, 1=LRT, 2=Bus, 3=Ferry
	AgencyID     string   `json:"agency_id"`     // Operating agency identifier
	LeadRoute    Route    `json:"-"`             // Representative route for legacy properties
}

// TrunkCorridor models a physical infrastructure segment carrying one or more ribbons.
type TrunkCorridor struct {
	CorridorID   string         `json:"corridor_id"`
	ArcID        int            `json:"arc_id"`
	Bundles      []*TrunkBundle `json:"bundles"`
	BundleSize   int            `json:"bundle_size"`
	CompositeKey string         `json:"composite_key"`
}

// ConsolidateCorridorBundles groups routes by agency and modal class, then clusters routes by
// trunk color using the provided ColorDistance interface. Enforces INV-CORR-01, INV-CORR-02.
func ConsolidateCorridorBundles(routes []Route, colorDist ColorDistance) ([]*TrunkBundle, error) {
	if len(routes) == 0 {
		return nil, nil
	}
	if colorDist == nil {
		colorDist = DefaultColorDistance
	}

	// 1. Deduplicate input routes by RouteID
	uniqueRoutes := make(map[string]Route)
	for _, r := range routes {
		uniqueRoutes[r.RouteID] = r
	}

	// 2. Partition routes by (AgencyID, ModalClass)
	// Prohibit cross-agency consolidation (INV-CORR-01)
	// Prohibit cross-mode consolidation
	type PartitionKey struct {
		AgencyID   string
		ModalClass int
	}

	partitions := make(map[PartitionKey][]Route)
	for _, r := range uniqueRoutes {
		agencyID := strings.TrimSpace(r.AgencyID)
		if agencyID == "" {
			agencyID = "default"
		}
		modalClass := ResolveModalClass(r.RouteType)
		key := PartitionKey{AgencyID: agencyID, ModalClass: modalClass}
		partitions[key] = append(partitions[key], r)
	}

	// 3. Cluster routes within each partition by ColorDistance
	var allBundles []*TrunkBundle

	// Sort partition keys for determinism
	var sortedPartitions []PartitionKey
	for k := range partitions {
		sortedPartitions = append(sortedPartitions, k)
	}
	sort.Slice(sortedPartitions, func(i, j int) bool {
		if sortedPartitions[i].ModalClass != sortedPartitions[j].ModalClass {
			return sortedPartitions[i].ModalClass < sortedPartitions[j].ModalClass
		}
		return sortedPartitions[i].AgencyID < sortedPartitions[j].AgencyID
	})

	for _, pKey := range sortedPartitions {
		partRoutes := partitions[pKey]

		// Sort routes by short name / ID for deterministic clustering
		sort.Slice(partRoutes, func(i, j int) bool {
			nameI := partRoutes[i].RouteShortName
			if nameI == "" {
				nameI = partRoutes[i].RouteID
			}
			nameJ := partRoutes[j].RouteShortName
			if nameJ == "" {
				nameJ = partRoutes[j].RouteID
			}
			return nameI < nameJ
		})

		type Cluster struct {
			RepColor   string
			LeadRoute  Route
			Routes     []Route
			RouteIDs   []string
			RouteNames []string
		}

		var clusters []*Cluster

		for _, r := range partRoutes {
			color := ResolveRouteColor(r)
			rName := r.RouteShortName
			if rName == "" {
				rName = r.RouteID
			}

			// Find matching cluster with distance <= threshold
			var matched *Cluster
			for _, c := range clusters {
				if colorDist.Distance(color, c.RepColor) <= ColorConsolidationThreshold {
					matched = c
					break
				}
			}

			if matched != nil {
				matched.Routes = append(matched.Routes, r)
				matched.RouteIDs = append(matched.RouteIDs, r.RouteID)
				matched.RouteNames = append(matched.RouteNames, rName)
			} else {
				clusters = append(clusters, &Cluster{
					RepColor:   color,
					LeadRoute:  r,
					Routes:     []Route{r},
					RouteIDs:   []string{r.RouteID},
					RouteNames: []string{rName},
				})
			}
		}

		for _, c := range clusters {
			sort.Strings(c.RouteIDs)
			sort.Strings(c.RouteNames)

			// Generate deterministic composite key
			cleanNames := make([]string, len(c.RouteNames))
			for i, name := range c.RouteNames {
				cleanNames[i] = sanitizeBadgeToken(name)
			}
			compKey := "badge_" + strings.Join(cleanNames, "_")

			bundle := &TrunkBundle{
				TrunkColor:   c.RepColor,
				RouteIDs:     c.RouteIDs,
				RouteNames:   c.RouteNames,
				CompositeKey: compKey,
				ModalClass:   pKey.ModalClass,
				AgencyID:     pKey.AgencyID,
				LeadRoute:    c.LeadRoute,
			}
			allBundles = append(allBundles, bundle)
		}
	}

	// 4. Deterministic Sort of all Bundles across corridor
	// Order by: ModalClass -> TrunkColor -> CompositeKey
	sort.Slice(allBundles, func(i, j int) bool {
		if allBundles[i].ModalClass != allBundles[j].ModalClass {
			return allBundles[i].ModalClass < allBundles[j].ModalClass
		}
		if allBundles[i].TrunkColor != allBundles[j].TrunkColor {
			return allBundles[i].TrunkColor < allBundles[j].TrunkColor
		}
		return allBundles[i].CompositeKey < allBundles[j].CompositeKey
	})

	bundleSize := len(allBundles)
	for i, b := range allBundles {
		b.BundleIndex = i
		b.BundleSize = bundleSize
	}

	// 5. Multiplicity Invariant Enforcement (INV-CORR-02)
	if bundleSize > 3 {
		return allBundles, fmt.Errorf("INV-CORR-02 violated: corridor bundle size %d exceeds ceiling of 3", bundleSize)
	}

	return allBundles, nil
}

// sanitizeBadgeToken cleans a route name for safe badge identifier keys
func sanitizeBadgeToken(name string) string {
	var sb strings.Builder
	for _, ch := range name {
		if (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') {
			sb.WriteRune(ch)
		} else {
			sb.WriteRune('_')
		}
	}
	res := sb.String()
	res = strings.Trim(res, "_")
	if res == "" {
		return "x"
	}
	return res
}
