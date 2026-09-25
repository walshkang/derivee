package gtfs

import (
	"sort"
	"strings"
)

// Standard route token normalization for NYC Subway (express variants -> base route)
var routeTokenClean = map[string]string{
	"6X": "6",
	"7X": "7",
	"FX": "F",
	"FS": "S",
	"GS": "S",
	"H":  "S",
	"SI": "SIR",
}

// CleanRouteToken normalizes express / shuttle variants to base public bullet names
func CleanRouteToken(token string) string {
	t := strings.TrimSpace(token)
	if clean, ok := routeTokenClean[t]; ok {
		return clean
	}
	return t
}

// ResolveArcBranchRoutes determines the precise subset of routes operating along each
// canonical arc in the network by projecting station candidates onto the topological graph
// and propagating service across zero-station connectors (switches, river tubes, express bypasses).
//
// This eliminates cartographic over-generalization where e.g. every orange corridor was
// labeled as "B, D, F, M", even in Queens where only F and M run, or the Bronx where only
// B and D run, or South Brooklyn where only F runs.
func ResolveArcBranchRoutes(
	ds *Dataset,
	graph *TopologyGraph,
	simplifiedArcs map[int][]Point2D,
	routeShapes map[string]map[string]bool,
) map[int]map[string][]string {
	if ds == nil || len(ds.Stops) == 0 || graph == nil {
		return nil
	}

	candidates := ExtractStationCandidates(ds)
	if len(candidates) == 0 {
		return nil
	}

	// 1. Identify which lead routes traverse each Arc
	arcLeadRoutes := make(map[int]map[string]bool)
	for routeID, shapesMap := range routeShapes {
		for shapeID := range shapesMap {
			for _, arcRef := range graph.ShapeArcs[shapeID] {
				if arcLeadRoutes[arcRef.ArcID] == nil {
					arcLeadRoutes[arcRef.ArcID] = make(map[string]bool)
				}
				arcLeadRoutes[arcRef.ArcID][routeID] = true
			}
		}
	}

	// 2. Map leadRouteID -> set of permitted member tokens
	leadFamilyTokens := make(map[string]map[string]bool)
	for routeID, route := range ds.Routes {
		name := route.RouteShortName
		if name == "" {
			name = routeID
		}
		leadFamilyTokens[routeID] = make(map[string]bool)
		for _, part := range strings.Split(name, ",") {
			part = CleanRouteToken(strings.TrimSpace(part))
			if part != "" {
				leadFamilyTokens[routeID][part] = true
			}
		}
	}

	// 3. Step 1: Direct station snapping to nearest arc
	// arcID -> leadRouteID -> set of active route tokens
	arcResolved := make(map[int]map[string]map[string]bool)
	for arcID := range simplifiedArcs {
		arcResolved[arcID] = make(map[string]map[string]bool)
	}

	for _, s := range candidates {
		minDist := 150.0 // Maximum snap distance (INV-CAPSULE-06)
		bestArc := -1
		for arcID, pts := range simplifiedArcs {
			if len(pts) < 2 {
				continue
			}
			proj, ok := ProjectStationToArc(s, pts, minDist)
			if ok && proj.DistanceM < minDist {
				minDist = proj.DistanceM
				bestArc = arcID
			}
		}

		if bestArc >= 0 {
			for leadID := range arcLeadRoutes[bestArc] {
				allowed := leadFamilyTokens[leadID]
				for sRoute := range s.RouteIDs {
					cleanSRoute := CleanRouteToken(sRoute)
					if allowed[cleanSRoute] {
						if arcResolved[bestArc][leadID] == nil {
							arcResolved[bestArc][leadID] = make(map[string]bool)
						}
						arcResolved[bestArc][leadID][cleanSRoute] = true
					}
				}
			}
		}
	}

	// 4. Step 2: Build graph adjacency between arcs sharing endpoints
	nodeArcs := make(map[PointKey][]int)
	for _, arc := range graph.Arcs {
		nodeArcs[arc.StartKey] = append(nodeArcs[arc.StartKey], arc.ID)
		nodeArcs[arc.EndKey] = append(nodeArcs[arc.EndKey], arc.ID)
	}

	// 5. Step 3: Multi-hop service propagation across zero-station connectors
	// Arcs lacking direct station stops (e.g. 46m switches, East River tubes) inherit
	// service from connected adjacent arcs carrying the same leadRouteID.
	for iter := 0; iter < 10; iter++ {
		changed := false
		for _, arc := range graph.Arcs {
			arcID := arc.ID
			for leadID := range arcLeadRoutes[arcID] {
				if len(arcResolved[arcID][leadID]) == 0 {
					adjacent := append(nodeArcs[arc.StartKey], nodeArcs[arc.EndKey]...)
					for _, neighborID := range adjacent {
						if neighborID == arcID {
							continue
						}
						if arcLeadRoutes[neighborID][leadID] && len(arcResolved[neighborID][leadID]) > 0 {
							if arcResolved[arcID][leadID] == nil {
								arcResolved[arcID][leadID] = make(map[string]bool)
							}
							for r := range arcResolved[neighborID][leadID] {
								arcResolved[arcID][leadID][r] = true
							}
							changed = true
						}
					}
				}
			}
		}
		if !changed {
			break
		}
	}

	// 6. Step 4: Convert resolved sets into sorted deterministic slices
	result := make(map[int]map[string][]string)
	for arcID, leadMap := range arcLeadRoutes {
		result[arcID] = make(map[string][]string)
		for leadID := range leadMap {
			routesSet := arcResolved[arcID][leadID]
			var sortedRoutes []string
			if len(routesSet) > 0 {
				for r := range routesSet {
					sortedRoutes = append(sortedRoutes, r)
				}
			} else {
				// Safety fallback to all tokens if propagation did not reach
				for r := range leadFamilyTokens[leadID] {
					sortedRoutes = append(sortedRoutes, r)
				}
			}
			sort.Strings(sortedRoutes)
			result[arcID][leadID] = sortedRoutes
		}
	}

	return result
}
