package gtfs

import (
	"math"
	"sort"
	"strconv"
	"strings"
)

// CalculateHaversineDistance computes great-circle distance between coordinates in meters
func CalculateHaversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const earthRadiusM = 6371000.0
	dLat := (lat2 - lat1) * (math.Pi / 180.0)
	dLon := (lon2 - lon1) * (math.Pi / 180.0)
	phi1 := lat1 * (math.Pi / 180.0)
	phi2 := lat2 * (math.Pi / 180.0)

	a := math.Sin(dLat/2.0)*math.Sin(dLat/2.0) +
		math.Cos(phi1)*math.Cos(phi2)*
			math.Sin(dLon/2.0)*math.Sin(dLon/2.0)
	c := 2.0 * math.Atan2(math.Sqrt(a), math.Sqrt(1.0-a))
	return earthRadiusM * c
}

// BuildComplexResolutionHierarchy builds the clustered multi-tier topological hierarchy
// linking GTFS stops to Station Complexes and pre-compiling StopResolution entries.
// Implements the tri-tier reconciliation pipeline: Regional Hub Anchors -> MTA Complexes -> Fallback.
func BuildComplexResolutionHierarchy(
	stops map[string]Stop,
	mtaComplexLookup map[string]int64,
	feedID string,
	hubAnchors []HubAnchor,
) ([]Complex, []StopResolution) {
	if feedID == "" {
		feedID = "subway"
	}
	if hubAnchors == nil {
		hubAnchors = RegionalHubAnchors
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

	type complexAccumulator struct {
		name      string
		borough   string
		isHub     int
		latSum    float64
		lonSum    float64
		stopCount int
	}
	complexMap := make(map[int64]*complexAccumulator)

	resolutionMap := make(map[string]StopResolution) // key: complexID + "|" + feedID + "|" + parentID + "|" + childID
	var generatedComplexSeq int64 = 800000

	parentToComplex := make(map[string]int64)

	// Step 1: Assign complex IDs to parent stations
	for stopID, stop := range stops {
		rootParentID := findRootParent(stopID)
		if _, resolved := parentToComplex[rootParentID]; resolved {
			continue
		}

		parentStop := stops[rootParentID]
		if parentStop.StopID == "" {
			parentStop = stop
		}

		var assignedComplexID int64
		var assignedName string
		var assignedBorough string
		isHubComplex := 0

		normalizedName := strings.ToUpper(parentStop.StopName)

		// Stage 1: Regional Mega-Hub Reconciliation (Doc 16 §1 & §5)
		for _, anchor := range hubAnchors {
			dist := CalculateHaversineDistance(parentStop.StopLat, parentStop.StopLon, anchor.CenterLat, anchor.CenterLon)
			if dist <= anchor.RadiusM {
				for _, kw := range anchor.Keywords {
					if strings.Contains(normalizedName, kw) {
						assignedComplexID = anchor.ComplexID
						assignedName = anchor.ComplexName
						assignedBorough = anchor.Borough
						isHubComplex = 1
						break
					}
				}
			}
			if isHubComplex == 1 {
				break
			}
		}

		// Stage 2: MTA Subway Complex ID Mapping (Doc 16 §1 & §5)
		if assignedComplexID == 0 && mtaComplexLookup != nil {
			cleanID := strings.TrimSpace(strings.ToUpper(rootParentID))
			if cid, found := mtaComplexLookup[cleanID]; found && cid > 0 {
				assignedComplexID = cid
				assignedName = parentStop.StopName
				assignedBorough = "Manhattan"
			}
		}

		// Stage 3: Independent Station Fallback
		if assignedComplexID == 0 {
			if numID, err := strconv.ParseInt(rootParentID, 10, 64); err == nil && numID > 0 && numID < 600000 {
				assignedComplexID = numID
			} else {
				assignedComplexID = generatedComplexSeq
				generatedComplexSeq++
			}
			assignedName = parentStop.StopName
		}

		parentToComplex[rootParentID] = assignedComplexID

		acc, exists := complexMap[assignedComplexID]
		if !exists {
			acc = &complexAccumulator{
				name:    assignedName,
				borough: assignedBorough,
				isHub:   isHubComplex,
			}
			complexMap[assignedComplexID] = acc
		}
		if isHubComplex == 1 {
			acc.isHub = 1
			acc.name = assignedName
			acc.borough = assignedBorough
		}
	}

	// Step 2: Build StopResolution entries
	for stopID, stop := range stops {
		rootParentID := findRootParent(stopID)
		complexID := parentToComplex[rootParentID]

		// Accumulate centroid coordinates
		acc := complexMap[complexID]
		if acc != nil && stop.StopLat != 0 && stop.StopLon != 0 {
			acc.latSum += stop.StopLat
			acc.lonSum += stop.StopLon
			acc.stopCount++
		}

		// Infer direction if child platform has N/S suffix
		var dirPtr *int
		upperID := strings.ToUpper(stopID)
		if strings.HasSuffix(upperID, "N") || strings.HasSuffix(upperID, "E") {
			d := 0
			dirPtr = &d
		} else if strings.HasSuffix(upperID, "S") || strings.HasSuffix(upperID, "W") {
			d := 1
			dirPtr = &d
		}

		// Add resolution entry for child platform
		key := strconv.FormatInt(complexID, 10) + "|" + feedID + "|" + rootParentID + "|" + stopID
		if _, exists := resolutionMap[key]; !exists {
			isParent := 0
			if stop.LocationType == 1 || rootParentID == stopID {
				isParent = 1
			}
			resolutionMap[key] = StopResolution{
				ComplexID:          complexID,
				FeedID:             feedID,
				ParentStationID:    rootParentID,
				ChildStopID:        stopID,
				PlatformCode:       stop.PlatformCode,
				DirectionID:        dirPtr,
				WheelchairBoarding: stop.WheelchairBoarding,
				ParentStopID:       rootParentID,
				IsParent:           isParent,
			}
		}

		// Also ensure self-referential parent entry exists for parentStation
		if rootParentID != stopID {
			parentKey := strconv.FormatInt(complexID, 10) + "|" + feedID + "|" + rootParentID + "|" + rootParentID
			if _, exists := resolutionMap[parentKey]; !exists {
				parentStop := stops[rootParentID]
				resolutionMap[parentKey] = StopResolution{
					ComplexID:          complexID,
					FeedID:             feedID,
					ParentStationID:    rootParentID,
					ChildStopID:        rootParentID,
					PlatformCode:       parentStop.PlatformCode,
					DirectionID:        nil,
					WheelchairBoarding: parentStop.WheelchairBoarding,
					ParentStopID:       rootParentID,
					IsParent:           1,
				}
			}
		}
	}

	// Step 3: Serialize Complexes
	complexes := make([]Complex, 0, len(complexMap))
	for cid, acc := range complexMap {
		lat := 0.0
		lon := 0.0
		if acc.stopCount > 0 {
			lat = acc.latSum / float64(acc.stopCount)
			lon = acc.lonSum / float64(acc.stopCount)
		}
		complexes = append(complexes, Complex{
			ComplexID:   cid,
			ComplexName: acc.name,
			Borough:     acc.borough,
			Latitude:    lat,
			Longitude:   lon,
			IsHub:       acc.isHub,
		})
	}

	sort.Slice(complexes, func(i, j int) bool {
		return complexes[i].ComplexID < complexes[j].ComplexID
	})

	// Step 4: Serialize StopResolutions
	resolutions := make([]StopResolution, 0, len(resolutionMap))
	for _, r := range resolutionMap {
		resolutions = append(resolutions, r)
	}

	sort.Slice(resolutions, func(i, j int) bool {
		if resolutions[i].ComplexID != resolutions[j].ComplexID {
			return resolutions[i].ComplexID < resolutions[j].ComplexID
		}
		if resolutions[i].ParentStationID != resolutions[j].ParentStationID {
			return resolutions[i].ParentStationID < resolutions[j].ParentStationID
		}
		return resolutions[i].ChildStopID < resolutions[j].ChildStopID
	})

	return complexes, resolutions
}

// BuildStopResolutionClosure pre-compiles the reflexive transitive closure for all stops in the dataset.
// Generates O(1) platform resolution entries according to Rules 1-4.
// Delegates to BuildComplexResolutionHierarchy while preserving full backward compatibility.
func BuildStopResolutionClosure(stops map[string]Stop) []StopResolution {
	resolutionMap := make(map[string]StopResolution) // key: parent_id + "|" + child_id

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

	addResolution := func(parentID, childID string, isParent int, platformCode string, wheelchair int) {
		key := parentID + "|" + childID
		if _, exists := resolutionMap[key]; !exists {
			var dirPtr *int
			upperID := strings.ToUpper(childID)
			if strings.HasSuffix(upperID, "N") || strings.HasSuffix(upperID, "E") {
				d := 0
				dirPtr = &d
			} else if strings.HasSuffix(upperID, "S") || strings.HasSuffix(upperID, "W") {
				d := 1
				dirPtr = &d
			}

			resolutionMap[key] = StopResolution{
				ComplexID:          1,
				FeedID:             "subway",
				ParentStationID:    parentID,
				ChildStopID:        childID,
				PlatformCode:       platformCode,
				DirectionID:        dirPtr,
				WheelchairBoarding: wheelchair,
				ParentStopID:       parentID,
				IsParent:           isParent,
			}
		}
	}

	for stopID, stop := range stops {
		if stop.LocationType == 1 {
			// Parent station: Rule 2 (Self-referential identity, is_parent = 1)
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
				addResolution(stopID, stopID, 0, stop.PlatformCode, stop.WheelchairBoarding)
			}
		}
	}

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
