package gtfs

import (
	"fmt"
	"math"
	"sort"
)

// PlatformCapsuleOptions configures platform capsule generation
type PlatformCapsuleOptions struct {
	TrackSpacingM    float64 // Track lateral spacing distance (default: 3.66m)
	HaloM            float64 // Halo margin extending past outer tracks (default: 2.5m)
	MaxSnapDistanceM float64 // Maximum distance to snap station to corridor arc (default: 150.0m, INV-CAPSULE-06)
	MergeRadiusM     float64 // Maximum distance along arc to merge adjacent platform nodes (default: 30.0m)
}

// DefaultPlatformCapsuleOptions provides standard production values
var DefaultPlatformCapsuleOptions = PlatformCapsuleOptions{
	TrackSpacingM:    BaseTrackSpacingM, // 3.66m
	HaloM:            2.5,
	MaxSnapDistanceM: 150.0,
	MergeRadiusM:     30.0,
}

// StationCandidate represents a transit station stop for platform capsule generation
type StationCandidate struct {
	ID        string
	Name      string
	Lat       float64
	Lon       float64
	RouteIDs  map[string]bool
	RouteList []string
}

// ExtractStationCandidates extracts rail/subway/LRT stations with their serving routes
func ExtractStationCandidates(ds *Dataset) []StationCandidate {
	if ds == nil || len(ds.Stops) == 0 {
		return nil
	}

	// 1. Map stop_id -> map[route_id]bool from trips and stop_times
	stopRoutes := make(map[string]map[string]bool)
	for tripID, stopTimes := range ds.StopTimes {
		trip, ok := ds.Trips[tripID]
		if !ok {
			continue
		}
		route, ok := ds.Routes[trip.RouteID]
		if !ok {
			continue
		}
		modalClass := ResolveModalClass(route.RouteType)
		// Only consider rail / subway / LRT for station platform capsules
		if modalClass != ModalClassSubway && modalClass != ModalClassLRT {
			continue
		}

		for _, st := range stopTimes {
			if stopRoutes[st.StopID] == nil {
				stopRoutes[st.StopID] = make(map[string]bool)
			}
			stopRoutes[st.StopID][route.RouteID] = true
		}
	}

	// 2. Group child stops by logical parent station or station ID
	type StationAccumulator struct {
		name      string
		latSum    float64
		lonSum    float64
		count     int
		parentLat float64
		parentLon float64
		hasParent bool
		routes    map[string]bool
	}

	accumulators := make(map[string]*StationAccumulator)

	for stopID, stop := range ds.Stops {
		rMap := stopRoutes[stopID]
		if len(rMap) == 0 {
			continue
		}

		stationKey := stop.ParentStation
		if stationKey == "" {
			stationKey = stopID
		}

		acc, exists := accumulators[stationKey]
		if !exists {
			stationName := stop.StopName
			if parent, ok := ds.Stops[stationKey]; ok && parent.StopName != "" {
				stationName = parent.StopName
			}
			acc = &StationAccumulator{
				name:   stationName,
				routes: make(map[string]bool),
			}
			if parent, ok := ds.Stops[stationKey]; ok && parent.StopLat != 0 && parent.StopLon != 0 {
				acc.parentLat = parent.StopLat
				acc.parentLon = parent.StopLon
				acc.hasParent = true
			}
			accumulators[stationKey] = acc
		}

		acc.latSum += stop.StopLat
		acc.lonSum += stop.StopLon
		acc.count++
		for rID := range rMap {
			acc.routes[rID] = true
		}
	}

	// 3. Assemble StationCandidate list
	var candidates []StationCandidate
	for stationID, acc := range accumulators {
		if len(acc.routes) == 0 {
			continue
		}

		var lat, lon float64
		if acc.hasParent {
			lat = acc.parentLat
			lon = acc.parentLon
		} else if acc.count > 0 {
			lat = acc.latSum / float64(acc.count)
			lon = acc.lonSum / float64(acc.count)
		} else {
			continue
		}

		var rList []string
		for rID := range acc.routes {
			rList = append(rList, rID)
		}
		sort.Strings(rList)

		candidates = append(candidates, StationCandidate{
			ID:        stationID,
			Name:      acc.name,
			Lat:       lat,
			Lon:       lon,
			RouteIDs:  acc.routes,
			RouteList: rList,
		})
	}

	// Deterministic sort by ID
	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].ID < candidates[j].ID
	})

	return candidates
}

// ProjectedStation holds the result of projecting a station onto a canonical arc
type ProjectedStation struct {
	Station    StationCandidate
	ArcID      int
	SegmentIdx int
	TParam     float64
	ProjPoint  Point2D
	DistanceM  float64
	Tangent    Vec2D
	Normal     Vec2D
}

// ProjectStationToArc projects a station candidate onto an arc in local metric space.
// Returns the projected point, unit tangent, unit normal, and distance in meters.
func ProjectStationToArc(station StationCandidate, arcPts []Point2D, maxSnapDist float64) (*ProjectedStation, bool) {
	if len(arcPts) < 2 {
		return nil, false
	}

	// Project arc points and station into local metric coordinates
	allPts := make([]Point2D, len(arcPts)+1)
	copy(allPts, arcPts)
	allPts[len(arcPts)] = Point2D{Lon: station.Lon, Lat: station.Lat}

	metricPts, refLat, refLon := ProjectToLocalM(allPts)
	metricArc := metricPts[:len(arcPts)]
	stationVec := metricPts[len(arcPts)]

	minDist := math.MaxFloat64
	bestSeg := -1
	bestT := 0.0
	var bestProj Vec2D
	var bestTangent Vec2D

	for i := 0; i < len(metricArc)-1; i++ {
		p0 := metricArc[i]
		p1 := metricArc[i+1]

		dx := p1.X - p0.X
		dy := p1.Y - p0.Y
		segLenSq := dx*dx + dy*dy
		if segLenSq < 1e-8 {
			continue
		}

		// Projection parameter t
		t := ((stationVec.X-p0.X)*dx + (stationVec.Y-p0.Y)*dy) / segLenSq
		tClamped := math.Max(0.0, math.Min(1.0, t))

		projX := p0.X + tClamped*dx
		projY := p0.Y + tClamped*dy

		distSq := (stationVec.X-projX)*(stationVec.X-projX) + (stationVec.Y-projY)*(stationVec.Y-projY)
		dist := math.Sqrt(distSq)

		if dist < minDist {
			minDist = dist
			bestSeg = i
			bestT = tClamped
			bestProj = Vec2D{X: projX, Y: projY}
			segLen := math.Sqrt(segLenSq)
			bestTangent = Vec2D{X: dx / segLen, Y: dy / segLen}
		}
	}

	if bestSeg == -1 || minDist > maxSnapDist {
		return nil, false
	}

	// Normal vector perpendicular to tangent (INV-CAPSULE-01: T · N = 0)
	normal := Vec2D{X: -bestTangent.Y, Y: bestTangent.X}

	projPt := UnprojectFromLocalM([]Vec2D{bestProj}, refLat, refLon)[0]

	return &ProjectedStation{
		Station:    station,
		SegmentIdx: bestSeg,
		TParam:     bestT,
		ProjPoint:  projPt,
		DistanceM:  minDist,
		Tangent:    bestTangent,
		Normal:     normal,
	}, true
}

// GeneratePlatformCapsules computes perpendicular platform capsules for stations along bundled corridors (K >= 2).
// GeneratePlatformCapsules computes perpendicular platform capsules for stations along bundled corridors (K >= 2)
// and stations bridging multi-color parallel corridors (e.g. Queens Plaza, Queensboro Plaza, Court Sq, 4th Ave-9th St).
func GeneratePlatformCapsules(
	ds *Dataset,
	simplifiedArcs map[int][]Point2D,
	arcBundles map[int][]*TrunkBundle,
	opts PlatformCapsuleOptions,
) ([]GeoJSONFeature, error) {
	if opts.TrackSpacingM <= 0 {
		opts.TrackSpacingM = BaseTrackSpacingM
	}
	if opts.HaloM <= 0 {
		opts.HaloM = 2.5
	}
	if opts.MaxSnapDistanceM <= 0 {
		opts.MaxSnapDistanceM = 150.0
	}
	if opts.MergeRadiusM <= 0 {
		opts.MergeRadiusM = 30.0
	}

	candidates := ExtractStationCandidates(ds)
	if len(candidates) == 0 {
		return nil, nil
	}

	// Index arc metadata
	type ArcMeta struct {
		ArcID      int
		Pts        []Point2D
		BundleSize int
		TrunkColor string
		ModalClass int
		Routes     []string
		RouteMap   map[string]bool
	}

	arcMetaMap := make(map[int]ArcMeta)
	for arcID, pts := range simplifiedArcs {
		if len(pts) < 2 {
			continue
		}
		bSize := 1
		tColor := ""
		mClass := ModalClassSubway
		var rNames []string
		rMap := make(map[string]bool)

		bundles := arcBundles[arcID]
		if len(bundles) > 0 {
			bSize = bundles[0].BundleSize
			tColor = bundles[0].TrunkColor
			mClass = bundles[0].ModalClass
			for _, b := range bundles {
				for _, rn := range b.RouteNames {
					if !rMap[rn] {
						rMap[rn] = true
						rNames = append(rNames, rn)
					}
				}
			}
		}

		arcMetaMap[arcID] = ArcMeta{
			ArcID:      arcID,
			Pts:        pts,
			BundleSize: bSize,
			TrunkColor: tColor,
			ModalClass: mClass,
			Routes:     rNames,
			RouteMap:   rMap,
		}
	}

	type RawCapsule struct {
		CentroidLat float64
		CentroidLon float64
		P1          [2]float64
		P2          [2]float64
		StationName string
		StopID      string
		CorridorID  string
		BundleSize  int
		ModalClass  int
		Routes      map[string]bool
	}

	var rawCapsules []RawCapsule

	// --- Track A: Intra-Arc Bundled Corridors (K >= 2) ---
	sortedArcIDs := make([]int, 0, len(arcMetaMap))
	for arcID := range arcMetaMap {
		sortedArcIDs = append(sortedArcIDs, arcID)
	}
	sort.Ints(sortedArcIDs)

	for _, arcID := range sortedArcIDs {
		meta := arcMetaMap[arcID]
		if meta.BundleSize < 2 {
			continue
		}

		var arcStations []ProjectedStation
		for _, station := range candidates {
			servesArc := false
			for _, rID := range meta.Routes {
				if station.RouteIDs[rID] {
					servesArc = true
					break
				}
			}

			proj, ok := ProjectStationToArc(station, meta.Pts, opts.MaxSnapDistanceM)
			if !ok {
				continue
			}

			if servesArc || proj.DistanceM <= 80.0 {
				proj.ArcID = arcID
				arcStations = append(arcStations, *proj)
			}
		}

		if len(arcStations) == 0 {
			continue
		}

		sort.Slice(arcStations, func(i, j int) bool {
			if arcStations[i].SegmentIdx != arcStations[j].SegmentIdx {
				return arcStations[i].SegmentIdx < arcStations[j].SegmentIdx
			}
			return arcStations[i].TParam < arcStations[j].TParam
		})

		var merged []ProjectedStation
		for _, s := range arcStations {
			if len(merged) == 0 {
				merged = append(merged, s)
				continue
			}
			prev := merged[len(merged)-1]
			distBetween := CalculateHaversineDistance(s.ProjPoint.Lat, s.ProjPoint.Lon, prev.ProjPoint.Lat, prev.ProjPoint.Lon)
			if distBetween < opts.MergeRadiusM {
				for rID := range s.Station.RouteIDs {
					prev.Station.RouteIDs[rID] = true
				}
				if s.DistanceM < prev.DistanceM {
					merged[len(merged)-1] = s
				}
			} else {
				merged = append(merged, s)
			}
		}

		K := meta.BundleSize
		spanM := float64(K-1)*opts.TrackSpacingM + 2.0*opts.HaloM
		halfSpanM := spanM / 2.0

		for _, s := range merged {
			refLat := s.ProjPoint.Lat
			refLon := s.ProjPoint.Lon
			radLat := refLat * math.Pi / 180.0
			cosLat := math.Cos(radLat)
			mPerDegLat := (math.Pi / 180.0) * EarthRadiusM
			mPerDegLon := mPerDegLat * cosLat

			dx1 := -halfSpanM * s.Normal.X
			dy1 := -halfSpanM * s.Normal.Y
			dx2 := halfSpanM * s.Normal.X
			dy2 := halfSpanM * s.Normal.Y

			p1 := [2]float64{refLon + (dx1 / mPerDegLon), refLat + (dy1 / mPerDegLat)}
			p2 := [2]float64{refLon + (dx2 / mPerDegLon), refLat + (dy2 / mPerDegLat)}

			rMap := make(map[string]bool)
			for rID := range s.Station.RouteIDs {
				rMap[rID] = true
			}

			rawCapsules = append(rawCapsules, RawCapsule{
				CentroidLat: refLat,
				CentroidLon: refLon,
				P1:          p1,
				P2:          p2,
				StationName: s.Station.Name,
				StopID:      s.Station.ID,
				CorridorID:  fmt.Sprintf("corridor_arc_%d", arcID),
				BundleSize:  K,
				ModalClass:  meta.ModalClass,
				Routes:      rMap,
			})
		}
	}

	// --- Track B: Inter-Arc Multi-Corridor Station Platform Connectors ---
	// For stations near >= 2 arcs with different trunk colors (Queens Plaza, Queensboro Plaza, Court Sq, 4th Ave-9th St, etc.)
	for _, station := range candidates {
		type ArcProjection struct {
			ArcID      int
			TrunkColor string
			ModalClass int
			ProjLat    float64
			ProjLon    float64
			ProjVec    Vec2D
			Tangent    Vec2D
			Normal     Vec2D
			DistanceM  float64
			Routes     []string
		}

		var nearbyProjs []ArcProjection
		colorsSeen := make(map[string]bool)

		for _, arcID := range sortedArcIDs {
			meta := arcMetaMap[arcID]

			// Check route match
			servesStation := false
			for _, r := range meta.Routes {
				if station.RouteIDs[r] {
					servesStation = true
					break
				}
			}

			proj, ok := ProjectStationToArc(station, meta.Pts, opts.MaxSnapDistanceM)
			if !ok {
				continue
			}

			// Gate: Station must either serve route on arc within opts.MaxSnapDistanceM, or physically snap within 85m
			if (servesStation && proj.DistanceM <= opts.MaxSnapDistanceM) || proj.DistanceM <= 85.0 {
				refLat := proj.ProjPoint.Lat
				refLon := proj.ProjPoint.Lon
				radLat := refLat * math.Pi / 180.0
				cosLat := math.Cos(radLat)
				mPerDegLat := (math.Pi / 180.0) * EarthRadiusM
				mPerDegLon := mPerDegLat * cosLat

				// Local metric vector relative to station
				dLon := (refLon - station.Lon) * mPerDegLon
				dLat := (refLat - station.Lat) * mPerDegLat

				colorKey := meta.TrunkColor
				if colorKey == "" {
					colorKey = fmt.Sprintf("arc_%d", arcID)
				}
				colorsSeen[colorKey] = true

				nearbyProjs = append(nearbyProjs, ArcProjection{
					ArcID:      arcID,
					TrunkColor: colorKey,
					ModalClass: meta.ModalClass,
					ProjLat:    refLat,
					ProjLon:    refLon,
					ProjVec:    Vec2D{X: dLon, Y: dLat},
					Tangent:    proj.Tangent,
					Normal:     proj.Normal,
					DistanceM:  proj.DistanceM,
					Routes:     meta.Routes,
				})
			}
		}

		// Only bridge if station touches >= 2 distinct trunk colors or corridors
		if len(colorsSeen) < 2 || len(nearbyProjs) < 2 {
			continue
		}

		// Find pair of projections with different trunk colors having maximum separation
		maxSep := 0.0
		bestA := -1
		bestB := -1

		for i := 0; i < len(nearbyProjs); i++ {
			for j := i + 1; j < len(nearbyProjs); j++ {
				pA := nearbyProjs[i]
				pB := nearbyProjs[j]
				if pA.TrunkColor == pB.TrunkColor {
					continue
				}

				dx := pB.ProjVec.X - pA.ProjVec.X
				dy := pB.ProjVec.Y - pA.ProjVec.Y
				sep := math.Sqrt(dx*dx + dy*dy)

				// Bridges must not exceed maximum platform span (120m)
				if sep <= 120.0 && sep > maxSep {
					maxSep = sep
					bestA = i
					bestB = j
				}
			}
		}

		if bestA == -1 || bestB == -1 {
			continue
		}

		projA := nearbyProjs[bestA]
		projB := nearbyProjs[bestB]

		radLat := station.Lat * math.Pi / 180.0
		cosLat := math.Cos(radLat)
		mPerDegLat := (math.Pi / 180.0) * EarthRadiusM
		mPerDegLon := mPerDegLat * cosLat

		K := len(colorsSeen)
		if K > 3 {
			K = 3
		}

		var p1, p2 [2]float64

		if maxSep >= 4.0 {
			// Bridge segment across the two projections with halo extension
			dx := projB.ProjVec.X - projA.ProjVec.X
			dy := projB.ProjVec.Y - projA.ProjVec.Y
			uX := dx / maxSep
			uY := dy / maxSep

			q1X := projA.ProjVec.X - opts.HaloM*uX
			q1Y := projA.ProjVec.Y - opts.HaloM*uY
			q2X := projB.ProjVec.X + opts.HaloM*uX
			q2Y := projB.ProjVec.Y + opts.HaloM*uY

			p1 = [2]float64{station.Lon + (q1X / mPerDegLon), station.Lat + (q1Y / mPerDegLat)}
			p2 = [2]float64{station.Lon + (q2X / mPerDegLon), station.Lat + (q2Y / mPerDegLat)}
		} else {
			// Centerlines nearly coincident: span along normal vector
			spanM := float64(K-1)*opts.TrackSpacingM + 2.0*opts.HaloM
			halfSpan := spanM / 2.0

			norm := projA.Normal
			dx1 := -halfSpan * norm.X
			dy1 := -halfSpan * norm.Y
			dx2 := halfSpan * norm.X
			dy2 := halfSpan * norm.Y

			p1 = [2]float64{projA.ProjLon + (dx1 / mPerDegLon), projA.ProjLat + (dy1 / mPerDegLat)}
			p2 = [2]float64{projA.ProjLon + (dx2 / mPerDegLon), projA.ProjLat + (dy2 / mPerDegLat)}
		}

		rMap := make(map[string]bool)
		for _, p := range nearbyProjs {
			for _, r := range p.Routes {
				rMap[r] = true
			}
		}
		for rID := range station.RouteIDs {
			rMap[rID] = true
		}

		rawCapsules = append(rawCapsules, RawCapsule{
			CentroidLat: station.Lat,
			CentroidLon: station.Lon,
			P1:          p1,
			P2:          p2,
			StationName: station.Name,
			StopID:      station.ID,
			CorridorID:  fmt.Sprintf("bridge_arc_%d_%d", projA.ArcID, projB.ArcID),
			BundleSize:  K,
			ModalClass:  projA.ModalClass,
			Routes:      rMap,
		})
	}

	if len(rawCapsules) == 0 {
		return nil, nil
	}

	// --- Deduplicate Raw Capsules within 30m ---
	sort.Slice(rawCapsules, func(i, j int) bool {
		if rawCapsules[i].StationName != rawCapsules[j].StationName {
			return rawCapsules[i].StationName < rawCapsules[j].StationName
		}
		return rawCapsules[i].StopID < rawCapsules[j].StopID
	})

	var deduped []RawCapsule
	for _, cap := range rawCapsules {
		merged := false
		for idx, existing := range deduped {
			dist := CalculateHaversineDistance(cap.CentroidLat, cap.CentroidLon, existing.CentroidLat, existing.CentroidLon)
			if dist < opts.MergeRadiusM {
				for r := range cap.Routes {
					deduped[idx].Routes[r] = true
				}
				if cap.BundleSize > deduped[idx].BundleSize {
					deduped[idx].BundleSize = cap.BundleSize
					deduped[idx].P1 = cap.P1
					deduped[idx].P2 = cap.P2
					deduped[idx].CorridorID = cap.CorridorID
				}
				merged = true
				break
			}
		}
		if !merged {
			deduped = append(deduped, cap)
		}
	}

	// Assemble final GeoJSON features
	var features []GeoJSONFeature
	for _, cap := range deduped {
		var rNames []string
		for r := range cap.Routes {
			rNames = append(rNames, r)
		}
		sort.Strings(rNames)

		casingWidthZ11, casingWidthZ14, casingWidthZ17 := CalculateCasingWidths(cap.BundleSize)

		// Canonical orientation of endpoints (INV-CORR-03)
		p1Key := ToPointKey(Point2D{Lon: cap.P1[0], Lat: cap.P1[1]})
		p2Key := ToPointKey(Point2D{Lon: cap.P2[0], Lat: cap.P2[1]})
		p1 := cap.P1
		p2 := cap.P2
		if !LessPointKey(p1Key, p2Key) && p1Key != p2Key {
			p1, p2 = p2, p1
		}

		arcLength := CalculateHaversineDistance(p1[1], p1[0], p2[1], p2[0])

		props := GeoJSONRouteProperties{
			FeatureType:    "platform_capsule",
			StationName:    cap.StationName,
			StopID:         cap.StopID,
			CorridorID:     cap.CorridorID,
			BundleSize:     cap.BundleSize,
			Routes:         rNames,
			ModalClass:     cap.ModalClass,
			TrunkColor:     "#FFFFFF",
			TrunkColorHex:  "#FFFFFF",
			CasingColor:    "#FFFFFF",
			CasingColorHex: "#FFFFFF",
			CasingWidth:    casingWidthZ14,
			CasingWidthZ11: casingWidthZ11,
			CasingWidthZ17: casingWidthZ17,
			CompositeKey:   fmt.Sprintf("capsule_%s", cap.StopID),
			ArcLengthM:     arcLength,
			SortKey:        1500, // Z-priority 1.5c
		}

		features = append(features, GeoJSONFeature{
			Type:       "Feature",
			Properties: props,
			Geometry: GeoJSONGeometry{
				Type:        "LineString",
				Coordinates: [][2]float64{p1, p2},
			},
		})
	}

	return features, nil
}
