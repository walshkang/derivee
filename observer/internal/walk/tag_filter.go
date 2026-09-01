package walk

import (
	"strings"
)

// WayFilterResult encapsulates the filtering and classification decision for an OSM way
type WayFilterResult struct {
	IsWalkable      bool
	IsBidirectional bool
	EdgeFlags       uint8
}

// NodeFilterResult encapsulates classification flags for an OSM node
type NodeFilterResult struct {
	IsWalkable bool
	NodeFlags  uint8
}

// EvaluateWay evaluates OSM way tags to determine if it is walkable and computes its EdgeFlags
func EvaluateWay(tags map[string]string) WayFilterResult {
	highway := tags["highway"]
	foot := tags["foot"]
	access := tags["access"]
	sidewalk := tags["sidewalk"]
	amenity := tags["amenity"]
	railway := tags["railway"]
	wheelchair := tags["wheelchair"]

	// 1. Check for elevator amenity / highway
	if amenity == "elevator" || highway == "elevator" {
		flags := FlagWalkable | FlagIsElevator
		if wheelchair != "no" {
			flags |= FlagWheelchairAccessible
		}
		return WayFilterResult{
			IsWalkable:      true,
			IsBidirectional: true,
			EdgeFlags:       flags,
		}
	}

	// 2. Check for subway entrance
	if railway == "subway_entrance" {
		flags := FlagWalkable
		if wheelchair == "yes" {
			flags |= FlagWheelchairAccessible
		}
		return WayFilterResult{
			IsWalkable:      true,
			IsBidirectional: true,
			EdgeFlags:       flags,
		}
	}

	// 3. Evaluate basic pedestrian highway types
	isWalkableHighway := false
	isSteps := false

	switch highway {
	case "footway", "pedestrian", "path", "living_street", "residential", "track", "service", "cycleway", "corridor", "bridleway", "crossing", "platform", "unclassified":
		isWalkableHighway = true
	case "steps":
		isWalkableHighway = true
		isSteps = true
	case "primary", "secondary", "tertiary", "primary_link", "secondary_link", "tertiary_link":
		// Allowed if explicit sidewalk or foot access
		if sidewalk != "" && sidewalk != "no" && sidewalk != "none" {
			isWalkableHighway = true
		} else if foot == "yes" || foot == "designated" || foot == "permissive" {
			isWalkableHighway = true
		} else if foot != "no" && access != "no" && access != "private" {
			// In urban environments, primary/secondary/tertiary often allow walking
			isWalkableHighway = true
		}
	case "motorway", "motorway_link", "trunk", "trunk_link":
		// Strictly non-walkable unless explicit foot/sidewalk tags override
		if foot == "yes" || foot == "designated" || (sidewalk != "" && sidewalk != "no" && sidewalk != "none") {
			isWalkableHighway = true
		}
	default:
		// Explicit foot tag
		if foot == "yes" || foot == "designated" || foot == "permissive" {
			isWalkableHighway = true
		}
	}

	if !isWalkableHighway {
		return WayFilterResult{IsWalkable: false}
	}

	// 4. Exclusion checks
	if foot == "no" {
		return WayFilterResult{IsWalkable: false}
	}
	if (access == "no" || access == "private") && (foot != "yes" && foot != "designated" && foot != "permissive") {
		return WayFilterResult{IsWalkable: false}
	}

	// 5. Compute EdgeFlags
	var flags uint8 = FlagWalkable

	if isSteps {
		flags |= FlagIsSteps
		// Steps are not wheelchair accessible unless explicit ramp or wheelchair=yes
		ramp := tags["ramp"]
		rampWheelchair := tags["ramp:wheelchair"]
		if wheelchair == "yes" || ramp == "yes" || rampWheelchair == "yes" {
			flags |= FlagWheelchairAccessible
		}
	} else {
		// Non-steps: wheelchair accessible unless explicit wheelchair=no or steep incline or rough surface
		if wheelchair == "no" {
			// Explicitly not accessible
		} else if wheelchair == "yes" || wheelchair == "designated" {
			flags |= FlagWheelchairAccessible
		} else {
			// Heuristic default: walkable paths without steps are wheelchair accessible
			// Check incline
			incline := tags["incline"]
			surface := tags["surface"]
			sacScale := tags["sac_scale"]
			if sacScale != "" && sacScale != "hiking" {
				// Mountain hiking trails not wheelchair accessible
			} else if incline == "steep" || isSteepIncline(incline) {
				// Steep incline (> 8%)
			} else if surface == "cobblestone" || surface == "unpaved" || surface == "gravel" || surface == "sand" || surface == "dirt" {
				// Rough surfaces
			} else {
				flags |= FlagWheelchairAccessible
			}
		}
	}

	// 6. Check directionality
	// In OSM, vehicular oneway does not apply to pedestrians unless oneway:foot=yes or oneway=foot
	isBidirectional := true
	onewayFoot := tags["oneway:foot"]
	if onewayFoot == "yes" || onewayFoot == "1" || tags["oneway"] == "foot" {
		isBidirectional = false
	}

	return WayFilterResult{
		IsWalkable:      true,
		IsBidirectional: isBidirectional,
		EdgeFlags:       flags,
	}
}

// EvaluateNode evaluates OSM node tags for elevator or subway entrance points
func EvaluateNode(tags map[string]string) NodeFilterResult {
	if len(tags) == 0 {
		return NodeFilterResult{IsWalkable: false}
	}

	amenity := tags["amenity"]
	highway := tags["highway"]
	railway := tags["railway"]
	wheelchair := tags["wheelchair"]

	if amenity == "elevator" || highway == "elevator" {
		var flags uint8 = FlagWalkable | FlagIsElevator
		if wheelchair != "no" {
			flags |= FlagWheelchairAccessible
		}
		return NodeFilterResult{IsWalkable: true, NodeFlags: flags}
	}

	if railway == "subway_entrance" {
		var flags uint8 = FlagWalkable
		if wheelchair == "yes" {
			flags |= FlagWheelchairAccessible
		}
		return NodeFilterResult{IsWalkable: true, NodeFlags: flags}
	}

	return NodeFilterResult{IsWalkable: false}
}

// isSteepIncline checks if a numerical incline value exceeds 8%
func isSteepIncline(incline string) bool {
	if incline == "" {
		return false
	}
	clean := strings.TrimSuffix(strings.TrimPrefix(incline, "-"), "%")
	clean = strings.TrimSpace(clean)
	var val float64
	var n int
	for _, ch := range clean {
		if ch >= '0' && ch <= '9' {
			val = val*10 + float64(ch-'0')
			n++
		} else if ch == '.' {
			break
		} else {
			return false
		}
	}
	if n > 0 && val > 8.0 {
		return true
	}
	return false
}
