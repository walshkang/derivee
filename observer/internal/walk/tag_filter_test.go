package walk

import (
	"testing"
)

func TestEvaluateWayWalkableHighways(t *testing.T) {
	walkableHighways := []string{
		"footway", "pedestrian", "path", "living_street", "residential",
		"service", "cycleway", "corridor", "bridleway", "crossing", "platform",
	}

	for _, h := range walkableHighways {
		res := EvaluateWay(map[string]string{"highway": h})
		if !res.IsWalkable {
			t.Errorf("highway=%s should be walkable", h)
		}
		if (res.EdgeFlags & FlagWalkable) == 0 {
			t.Errorf("highway=%s should have FlagWalkable set", h)
		}
		if (res.EdgeFlags & FlagWheelchairAccessible) == 0 {
			t.Errorf("highway=%s should default to wheelchair accessible", h)
		}
		if !res.IsBidirectional {
			t.Errorf("highway=%s should be bidirectional", h)
		}
	}
}

func TestEvaluateWaySteps(t *testing.T) {
	// Basic steps: walkable, is_steps, NOT wheelchair accessible
	res1 := EvaluateWay(map[string]string{"highway": "steps"})
	if !res1.IsWalkable {
		t.Errorf("steps should be walkable")
	}
	if (res1.EdgeFlags & FlagIsSteps) == 0 {
		t.Errorf("steps should have FlagIsSteps set")
	}
	if (res1.EdgeFlags & FlagWheelchairAccessible) != 0 {
		t.Errorf("steps without ramp should not be wheelchair accessible")
	}

	// Steps with ramp: wheelchair accessible
	res2 := EvaluateWay(map[string]string{
		"highway": "steps",
		"ramp":    "yes",
	})
	if (res2.EdgeFlags & FlagWheelchairAccessible) == 0 {
		t.Errorf("steps with ramp=yes should be wheelchair accessible")
	}

	// Steps with wheelchair=yes
	res3 := EvaluateWay(map[string]string{
		"highway":    "steps",
		"wheelchair": "yes",
	})
	if (res3.EdgeFlags & FlagWheelchairAccessible) == 0 {
		t.Errorf("steps with wheelchair=yes should be wheelchair accessible")
	}
}

func TestEvaluateWayElevator(t *testing.T) {
	res := EvaluateWay(map[string]string{"highway": "elevator"})
	if !res.IsWalkable {
		t.Errorf("elevator should be walkable")
	}
	if (res.EdgeFlags & FlagIsElevator) == 0 {
		t.Errorf("elevator should have FlagIsElevator set")
	}
	if (res.EdgeFlags & FlagWheelchairAccessible) == 0 {
		t.Errorf("elevator should be wheelchair accessible by default")
	}

	resNoWC := EvaluateWay(map[string]string{
		"amenity":    "elevator",
		"wheelchair": "no",
	})
	if (resNoWC.EdgeFlags & FlagWheelchairAccessible) != 0 {
		t.Errorf("elevator with wheelchair=no should not be wheelchair accessible")
	}
}

func TestEvaluateWayExclusions(t *testing.T) {
	// Motorway without sidewalk
	res1 := EvaluateWay(map[string]string{"highway": "motorway"})
	if res1.IsWalkable {
		t.Errorf("motorway without sidewalk should NOT be walkable")
	}

	// Foot=no
	res2 := EvaluateWay(map[string]string{
		"highway": "residential",
		"foot":    "no",
	})
	if res2.IsWalkable {
		t.Errorf("highway with foot=no should NOT be walkable")
	}

	// Access=private without foot=yes
	res3 := EvaluateWay(map[string]string{
		"highway": "residential",
		"access":  "private",
	})
	if res3.IsWalkable {
		t.Errorf("access=private should NOT be walkable")
	}

	// Access=private WITH foot=yes
	res4 := EvaluateWay(map[string]string{
		"highway": "residential",
		"access":  "private",
		"foot":    "yes",
	})
	if !res4.IsWalkable {
		t.Errorf("access=private with foot=yes SHOULD be walkable")
	}
}

func TestEvaluateWayOneway(t *testing.T) {
	// Vehicular oneway=yes still allows pedestrian bidirectional
	res1 := EvaluateWay(map[string]string{
		"highway": "residential",
		"oneway":  "yes",
	})
	if !res1.IsBidirectional {
		t.Errorf("vehicular oneway should allow bidirectional pedestrian travel")
	}

	// Explicit pedestrian oneway
	res2 := EvaluateWay(map[string]string{
		"highway":     "footway",
		"oneway:foot": "yes",
	})
	if res2.IsBidirectional {
		t.Errorf("oneway:foot=yes should enforce directional travel")
	}
}

func TestEvaluateNode(t *testing.T) {
	res1 := EvaluateNode(map[string]string{"amenity": "elevator"})
	if !res1.IsWalkable {
		t.Errorf("node with amenity=elevator should be walkable")
	}
	if (res1.NodeFlags & FlagIsElevator) == 0 {
		t.Errorf("node should have FlagIsElevator")
	}

	res2 := EvaluateNode(map[string]string{
		"railway":    "subway_entrance",
		"wheelchair": "yes",
	})
	if !res2.IsWalkable {
		t.Errorf("subway entrance should be walkable")
	}
	if (res2.NodeFlags & FlagWheelchairAccessible) == 0 {
		t.Errorf("subway entrance with wheelchair=yes should have FlagWheelchairAccessible")
	}
}
