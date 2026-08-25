package gtfs

import (
	"sort"
)

// BuildStopResolutionClosure pre-compiles the reflexive transitive closure for all stops in the dataset.
// Generates O(1) platform resolution entries according to Rules 1-4.
func BuildStopResolutionClosure(stops map[string]Stop) []StopResolution {
	resolutionMap := make(map[string]StopResolution) // key: parent_id + "|" + child_id

	addResolution := func(parentID, childID string, isParent int, platformCode string, wheelchair int) {
		key := parentID + "|" + childID
		if _, exists := resolutionMap[key]; !exists {
			resolutionMap[key] = StopResolution{
				ParentStopID:       parentID,
				ChildStopID:        childID,
				IsParent:           isParent,
				PlatformCode:       platformCode,
				WheelchairBoarding: wheelchair,
			}
		}
	}

	// Helper to find root parent station if hierarchical chain exists
	findRootParent := func(stopID string) string {
		currID := stopID
		visited := make(map[string]bool)
		for {
			if visited[currID] {
				break
			}
			visited[currID] = true

			stop, ok := stops[currID]
			if !ok || stop.ParentStation == "" || stop.ParentStation == currID {
				break
			}
			currID = stop.ParentStation
		}
		return currID
	}

	for stopID, stop := range stops {
		if stop.LocationType == 1 {
			// Parent station
			// Rule 2: Parent Station -> Parent Station (Self-referential identity, is_parent = 1)
			addResolution(stopID, stopID, 1, stop.PlatformCode, stop.WheelchairBoarding)
		} else {
			// Child platform or standalone stop
			rootParentID := findRootParent(stopID)

			if rootParentID != stopID {
				// Has a valid parent station
				parentStop, hasParent := stops[rootParentID]
				parentWheelchair := 0
				if hasParent {
					parentWheelchair = parentStop.WheelchairBoarding
				}

				// Rule 1: Parent Station -> Child Platform (is_parent = 0)
				addResolution(rootParentID, stopID, 0, stop.PlatformCode, stop.WheelchairBoarding)

				// Rule 2: Parent Station -> Parent Station (Self-referential identity, is_parent = 1)
				addResolution(rootParentID, rootParentID, 1, "", parentWheelchair)

				// Rule 3: Child Platform -> Parent Station (Reverse lookup, is_parent = 1)
				addResolution(stopID, rootParentID, 1, "", parentWheelchair)

				// Rule 4: Child Platform -> Child Platform (Self-referential identity, is_parent = 0)
				addResolution(stopID, stopID, 0, stop.PlatformCode, stop.WheelchairBoarding)
			} else {
				// Standalone stop (no parent station)
				// Self-referential entry
				addResolution(stopID, stopID, 0, stop.PlatformCode, stop.WheelchairBoarding)
			}
		}
	}

	// Convert to sorted slice
	result := make([]StopResolution, 0, len(resolutionMap))
	for _, res := range resolutionMap {
		result = append(result, res)
	}

	sort.Slice(result, func(i, j int) bool {
		if result[i].ParentStopID != result[j].ParentStopID {
			return result[i].ParentStopID < result[j].ParentStopID
		}
		return result[i].ChildStopID < result[j].ChildStopID
	})

	return result
}
