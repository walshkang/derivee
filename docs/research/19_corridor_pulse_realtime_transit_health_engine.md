# Corridor Pulse: Real-Time Transit Health Engine Architecture and Headway Regularity Analytics

## 1. Mathematical Foundations of Headway Regularity and Spatial-Temporal Anomaly Detection

High-frequency scheduled transit networks rely on temporal consistency rather than strict timetable adherence. When passenger arrival rates at stations follow a continuous Poisson process, the expected passenger waiting time depends directly on the variance of vehicle headways. To model an active corridor, let a route polyline $R$ be parameterized by its one-dimensional curvilinear distance offset from the terminal origin, $s \in [0, L]$, where $L$ represents the total corridor length.

At any discrete evaluation epoch $t$, a fleet of $k$ active vehicles operates along the corridor. Their measured linear distance offsets along the route form an ordered array $D = \langle d_1, d_2, \dots, d_k \rangle$ satisfying $0 \le d_1 < d_2 < \dots < d_k \le L$, where vehicle indices increase in the direction of travel such that vehicle $i+1$ leads vehicle $i$.

### Spatial and Projected Temporal Headways
The spatial interval separating vehicle $i$ from its immediate downstream leader $i+1$ is defined by:
$$\Delta d_i = d_{i+1} - d_i$$

For the leading vehicle $k$, the headway is evaluated relative to the route terminus $L$ or wrapped dynamically around a circular route topology.

While automated vehicle location (AVL) and GPS telemetry stream spatial positions, headway regulation is experienced by passengers temporally. Converting spatial headway $\Delta d_i$ to projected temporal headway $h_i$ requires integrating the historical or real-time harmonic mean speed $\bar{v}_s$ over the traversed corridor segment $[d_i, d_{i+1}]$:
$$h_i = \int_{d_i}^{d_{i+1}} \frac{1}{v(s)} \, ds \approx \frac{\Delta d_i}{\bar{v}_{[d_i, d_{i+1}]}}$$

When real-time link-level speeds are unavailable, $\bar{v}$ is estimated via scheduled travel-time matrices or recent probe velocities. Given a nominal scheduled headway $H_{\text{sched}}$, the system tracks normalized headway deviations:
$$\delta_i = \frac{h_i}{H_{\text{sched}}}$$

### Mathematical Thresholds for Bunching and Service Gaps
Vehicle bunching occurs when the trailing vehicle's headway degrades below a critical fraction of the scheduled service interval, indicating that the following vehicle has effectively caught up to the leader's passenger catchment zone:
$$\text{Bunching Condition:} \quad h_i < \alpha \cdot H_{\text{sched}} \quad \text{where} \quad \alpha \in [0.20, 0.30]$$

Adopting the Transit Capacity and Quality of Service Manual (TCQSM) standard, setting $\alpha = 0.25$ provides an optimal balance between false positives and operational intervention thresholds:
$$\Delta d_i < 0.25 \cdot H_{\text{sched}} \cdot \bar{v}_{[d_i, d_{i+1}]}$$

Conversely, a service gap occurs when headway stretches beyond acceptable limits, imposing severe passenger queue inflation and platform overcrowding:
$$\text{Service Gap Condition:} \quad h_i > \beta \cdot H_{\text{sched}} \quad \text{where} \quad \beta \in [1.50, 2.00]$$

Calibrating $\beta = 1.75$ captures acute service deficits before waiting time escalations become critical.

### Physical and Operational Dynamics of the Runaway Platooning Mechanism
Vehicle bunching is governed by a non-linear positive feedback loop driven by passenger boarding physics. Station dwell time $t_{\text{dwell}}$ is a direct function of passenger accumulation $P_{\text{wait}}$, clearance time $t_{\text{clear}}$, and boarding rate per passenger $t_{\text{board}}$:
$$t_{\text{dwell}} = t_{\text{clear}} + t_{\text{board}} \cdot P_{\text{wait}}$$

Under a steady passenger arrival rate $\lambda$, the volume of passengers waiting at a downstream station for vehicle $i$ is proportional to its actual headway:
$$P_{\text{wait}} = \lambda \cdot h_i \quad \implies \quad t_{\text{dwell}}(i) = t_{\text{clear}} + t_{\text{board}} \cdot \lambda \cdot h_i$$

If vehicle $i$ suffers an initial stochastic delay $\epsilon$, its headway expands to $h_i' = H_{\text{sched}} + \epsilon$, causing the vehicle to encounter an inflated passenger volume $P_{\text{wait}}' = \lambda (H_{\text{sched}} + \epsilon)$ at the next station. This increases its dwell time by $\Delta t_{\text{dwell}} = t_{\text{board}} \cdot \lambda \cdot \epsilon$, further widening the headway $h_i$ at downstream stops.

Concurrently, the trailing vehicle $i-1$ operates with a compressed headway $h_{i-1}' = H_{\text{sched}} - \epsilon$. It arrives at stations cleared moments earlier by vehicle $i$, encountering a depleted passenger queue $P_{\text{wait}}(i-1) = \lambda (H_{\text{sched}} - \epsilon)$. The trailing vehicle spends less time boarding passengers, accelerates through the corridor, and rapidly overtakes the leading vehicle. Thus, a bunching pair ($\Delta d_i \to 0$) is causally linked to an upstream service gap ($\Delta d_{i-1} \gg H_{\text{sched}} \cdot \bar{v}$), causing vehicles along high-frequency lines to collapse into multi-vehicle platoons followed by major service voids.

---

## 2. Statistical Dispersion and Corridor Health Scoring Architecture

### Statistical Dispersion: Coefficient of Variation vs. Gini Coefficient
Evaluating corridor health requires quantifying the spatial and temporal uniformity of the vehicle fleet. The Osuna-Newell and Welman models link temporal headway dispersion to expected passenger waiting time $E[W]$ under random passenger arrivals:
$$E[W] = \frac{\mu_h}{2} \left(1 + CV_h^2\right) = \frac{\mu_h}{2} \left(1 + \frac{\sigma_h^2}{\mu_h^2}\right)$$
where $\mu_h$ is the empirical mean headway and $\sigma_h$ is the standard deviation:
$$\mu_h = \frac{1}{n}\sum_{i=1}^n h_i, \quad \sigma_h = \sqrt{\frac{1}{n}\sum_{i=1}^n (h_i - \mu_h)^2}, \quad CV_h = \frac{\sigma_h}{\mu_h}$$

When service is perfectly regular ($h_i = \mu_h, \forall i$), $CV_h = 0$, and average wait time is half the headway ($E[W] = \mu_h / 2$). When $CV_h = 1.0$ (exponentially distributed uncoordinated arrivals), expected waiting time doubles to $E[W] = \mu_h$.

The Gini Coefficient measures relative inequality across the headway distribution:
$$G_h = \frac{\sum_{i=1}^n \sum_{j=1}^n \vert h_i - h_j \vert}{2n^2 \mu_h} = \frac{2 \sum_{i=1}^n i \cdot h_{(i)}}{n \sum_{i=1}^n h_{(i)}} - \frac{n + 1}{n}$$
For small fleets ($n < 10$), finite-sample correction is required: $G_h^* = \frac{n}{n-1} G_h$.

### Dispersion Metric Comparison

| Evaluative Criterion | Coefficient of Variation ($CV_h = \sigma/\mu$) | Gini Coefficient ($G_h$) | Architectural Trade-Off Analysis |
|:---|:---|:---|:---|
| **Computational Complexity** | $\mathcal{O}(n)$ single-pass via Welford’s algorithm | $\mathcal{O}(n \log n)$ due to mandatory array sorting | $CV_h$ executes in $<1\,\mu\text{s}$ for $n=50$; $G_h$ requires memory allocation and sorting. |
| **Mathematical Domain** | $[0, \sqrt{n - 1}]$; can exceed $1.0$ under severe clustering | $[0, 1]$; strictly bounded | $CV_h$ requires non-linear compression to fit fixed metric bounds ($0\text{--}100$). |
| **Passenger Wait Correlation**| Exact analytical linkage via Osuna-Newell identity | Non-linear correlation; lacks direct wait time mapping | $CV_h$ directly quantifies passenger delay costs and operational penalties. |
| **Sensitivity to Small Fleets**| Moderately sensitive to single vehicle outliers | Underestimates inequality without correction factor | $CV_h$ performs predictably on low-frequency corridors ($n=3\text{ to }5$). |
| **Sensitivity to Platoons** | Strongly penalizes isolated pairs via $(h_i - \mu_h)^2$ | Linearly weights differences; dilutes pairs across routes | $CV_h$ detects early-stage bunching before whole-corridor collapse. |

Because transit service quality is defined by passenger waiting times, the **Coefficient of Variation ($CV_h$)** serves as the primary analytical foundation for corridor health scoring.

### TCQSM Level of Service (LOS) Benchmarks

| Level of Service (LOS) | Headway Coefficient of Variation ($CV_h$) | Probability of Outlier Headway ($\vert h_i - H \vert > 0.5H$) | Operational Description | Wait Time Multiplier Factor ($1 + CV_h^2$) |
|:---:|:---:|:---:|:---|:---:|
| **A** | $0.00 - 0.21$ | $\le 1\%$ | Service operates like clockwork; zero platooning. | $1.00 - 1.04$ |
| **B** | $0.22 - 0.30$ | $\approx 10\%$ | Vehicles slightly off headway; imperceptible delay. | $1.05 - 1.09$ |
| **C** | $0.31 - 0.39$ | $\approx 20\%$ | Noticeable headway variability; minor bunching onset. | $1.10 - 1.15$ |
| **D** | $0.40 - 0.52$ | $\approx 33\%$ | Irregular intervals; frequent localized bunching. | $1.16 - 1.27$ |
| **E** | $0.53 - 0.74$ | $\approx 50\%$ | Chronic instability; frequent multi-vehicle platoons. | $1.28 - 1.55$ |
| **F** | $\ge 0.75$ | $> 50\%$ | Complete service breakdown; majority of fleet bunched. | $> 1.56$ |

### Normalized Corridor Health Score Formulation
The Corridor Health Score $S_{\text{corridor}} \in [0, 100]$ combines continuous headway uniformity via an exponential decay function anchored to the TCQSM LOS F threshold ($CV_h = 0.75$) with discrete penalty subtractions for bunching events ($N_{\text{bunch}}$) and service gaps ($N_{\text{gap}}$):

$$S_{\text{corridor}} = \max\left(0.0, \, \min\left(100.0, \, 100 \cdot \exp(-1.60 \cdot CV_h) - (w_b \cdot N_{\text{bunch}} + w_g \cdot N_{\text{gap}})\right)\right)$$
where $w_b = 15.0$ per bunched vehicle pair, and $w_g = 10.0$ per service gap.

### Tri-Tier Discrete Status Classification Logic
$$\text{Status} = \begin{cases}  \mathbf{Good} & \text{if } S_{\text{corridor}} \ge 75.0 \quad \wedge \quad N_{\text{bunch}} = 0 \\ \mathbf{Gaps} & \text{if } (50.0 \le S_{\text{corridor}} < 75.0 \quad \wedge \quad N_{\text{bunch}} = 0) \quad \vee \quad (N_{\text{gap}} > 0 \quad \wedge \quad N_{\text{bunch}} = 0) \\ \mathbf{Delayed} & \text{if } S_{\text{corridor}} < 50.0 \quad \vee \quad N_{\text{bunch}} > 0 \end{cases}$$

Any corridor containing an active bunching event is immediately downgraded to **Delayed**, reflecting systemic vehicle regulation failure.

---

## 3. MapLibre Visualization Architecture

Rendering high-frequency real-time transit telemetry (50–500 active vehicles updated every 1–2 seconds) requires balancing client battery consumption, frame pacing, and main-thread responsiveness within an $8.33\,\text{ms}$ (120 FPS) or $16.66\,\text{ms}$ (60 FPS) frame budget.

### Dynamic MLNShapeSource vs. Dedicated Point Feature Views

| Architectural Dimension | Dynamic `MLNShapeSource` (Symbol / Circle Layers) | Dedicated Point Feature View / Core Animations |
|:---|:---|:---|
| **Data Flow Pipeline** | GeoJSON Shape $\to$ C++ Tile Parser $\to$ Vector Tile Feature $\to$ Worker Tessellation $\to$ GPU Vertex Buffer | CoreAnimation `CALayer` or Direct Metal Node Translation updating screen-space transform matrices |
| **Main-Thread Latency** | High overhead if GeoJSON serialization occurs on main run loop; triggers frame drops during gestures | Minimal main-thread CPU overhead; property updates translate directly to coordinate shifts |
| **GPU Tessellation Overhead** | Re-tessellates point features across intersecting tile boundaries on every data assignment | Zero geometry re-tessellation; point quads remain static in memory, transforming via vertex uniform matrices |
| **Visual Capacity** | Handles 10,000+ points simultaneously using GPU instancing; supports clustering and expressions | Degrades when managing $>150$ active views due to UIKit/CoreAnimation compositing limits |
| **Dynamic Interpolation** | Difficult to achieve native 60–120fps tweening directly through shape-source replacements | Enables native 60–120fps hardware-accelerated movement interpolation between telemetry ticks |

### Maintaining 60–120 FPS During Real-Time Telemetry Updates
1. **Source Decoupling:** Static route polylines are placed into an immutable vector source, reserving dynamic shape sources exclusively for transient vehicle markers and bunching segments.
2. **Background Deserialization:** GTFS-RT Protobuf feeds are deserialized into native `MLNPointFeature` instances on a background dispatch queue before passing the final shape collection to the main run loop.
3. **Decoupled Camera Control:** Camera position commands are completely decoupled from network ingestion cycles, preventing telemetry arrivals from re-triggering map redraw loops.
4. **Linear Dead-Reckoning (LERP):** Interpolates coordinates between discrete GPS ticks using a display link loop:
   $$\vec{P}(t) = \vec{P}_{\text{prev}} + t \cdot (\vec{P}_{\text{target}} - \vec{P}_{\text{prev}}), \quad \theta(t) = \theta_{\text{prev}} + t \cdot \Delta\theta$$
5. **GPU Pitch & Rotation Alignment:** Configures `circlePitchAlignment = "map"` and `iconRotationAlignment = "map"`, locking markers to the terrain surface during tilt and rotation.

---

## 4. Real-Time Engine Implementation: Go Algorithm

```go
package health

import (
	"errors"
	"math"
	"sort"
)

const (
	BunchingThresholdFactor   = 0.25
	ServiceGapThresholdFactor = 1.75
	KappaMetricParam          = 1.60
	WeightBunchPenalty        = 15.0
	WeightGapPenalty          = 10.0
)

type CorridorStatus string

const (
	StatusGood    CorridorStatus = "Good"
	StatusGaps    CorridorStatus = "Gaps"
	StatusDelayed CorridorStatus = "Delayed"
)

type ActiveVehicleInput struct {
	VehicleID          string  `json:"vehicle_id"`
	CurvilinearOffsetM float64 `json:"curvilinear_offset_m"`
	SpeedMetersPerSec  float64 `json:"speed_mps"`
	DelaySec           int64   `json:"delay_sec"`
	IsTargetVehicle    bool    `json:"is_target"`
	Bearing            float64 `json:"bearing"`
}

type VehicleClassification struct {
	VehicleID       string  `json:"vehicle_id"`
	SpatialHeadwayM float64 `json:"spatial_headway_m"`
	TemporalHeadway float64 `json:"temporal_headway_sec"`
	IsBunched       bool    `json:"is_bunched"`
	IsServiceGap    bool    `json:"is_service_gap"`
}

type CorridorHealthResult struct {
	RouteID             string                  `json:"route_id"`
	VehicleCount        int                     `json:"vehicle_count"`
	ScheduledHeadwaySec float64                 `json:"scheduled_headway_sec"`
	MeanHeadwaySec      float64                 `json:"mean_headway_sec"`
	HeadwayStdDevSec    float64                 `json:"headway_std_dev_sec"`
	CoefficientOfVar    float64                 `json:"coefficient_of_variation"`
	GiniCoefficient     float64                 `json:"gini_coefficient"`
	BunchingEventCount  int                     `json:"bunching_event_count"`
	ServiceGapCount     int                     `json:"service_gap_count"`
	CorridorHealthScore float64                 `json:"corridor_health_score"`
	Status              CorridorStatus          `json:"corridor_status"`
	Classifications     []VehicleClassification `json:"classifications"`
}

func AnalyzeCorridorRegularity(
	routeID string,
	vehicles []ActiveVehicleInput,
	schedHeadwaySec float64,
	nominalSpeedMPS float64,
) (*CorridorHealthResult, error) {
	n := len(vehicles)
	if n < 2 {
		return nil, errors.New("insufficient vehicles active on corridor to assess headway regularity")
	}
	if schedHeadwaySec <= 0 {
		return nil, errors.New("scheduled headway must be strictly positive")
	}
	if nominalSpeedMPS <= 0 {
		nominalSpeedMPS = 12.0
	}

	sortedVehicles := make([]ActiveVehicleInput, n)
	copy(sortedVehicles, vehicles)
	sort.Slice(sortedVehicles, func(i, j int) bool {
		return sortedVehicles[i].CurvilinearOffsetM < sortedVehicles[j].CurvilinearOffsetM
	})

	headwayCount := n - 1
	temporalHeadways := make([]float64, headwayCount)
	classifications := make([]VehicleClassification, n)

	bunchCount := 0
	gapCount := 0

	var sumHeadway float64
	var sumSqHeadway float64

	bunchingThreshold := BunchingThresholdFactor * schedHeadwaySec
	gapThreshold := ServiceGapThresholdFactor * schedHeadwaySec

	for i := 0; i < headwayCount; i++ {
		follower := sortedVehicles[i]
		leader := sortedVehicles[i+1]

		deltaD := leader.CurvilinearOffsetM - follower.CurvilinearOffsetM
		if deltaD < 0 {
			deltaD = 0
		}

		effectiveSpeed := follower.SpeedMetersPerSec
		if effectiveSpeed < 2.5 {
			effectiveSpeed = nominalSpeedMPS
		}

		tHeadway := deltaD / effectiveSpeed
		temporalHeadways[i] = tHeadway

		sumHeadway += tHeadway
		sumSqHeadway += tHeadway * tHeadway

		isBunched := tHeadway < bunchingThreshold
		isGap := tHeadway > gapThreshold

		if isBunched {
			bunchCount++
		}
		if isGap {
			gapCount++
		}

		classifications[i] = VehicleClassification{
			VehicleID:       follower.VehicleID,
			SpatialHeadwayM: deltaD,
			TemporalHeadway: tHeadway,
			IsBunched:       isBunched,
			IsServiceGap:    isGap,
		}
	}

	classifications[n-1] = VehicleClassification{
		VehicleID:       sortedVehicles[n-1].VehicleID,
		SpatialHeadwayM: 0,
		TemporalHeadway: schedHeadwaySec,
		IsBunched:       false,
		IsServiceGap:    false,
	}

	fHeadwayCount := float64(headwayCount)
	meanHeadway := sumHeadway / fHeadwayCount

	variance := (sumSqHeadway / fHeadwayCount) - (meanHeadway * meanHeadway)
	if variance < 0 {
		variance = 0
	}
	stdDev := math.Sqrt(variance)

	cv := 0.0
	if meanHeadway > 0 {
		cv = stdDev / meanHeadway
	}

	sortedHeadways := make([]float64, headwayCount)
	copy(sortedHeadways, temporalHeadways)
	sort.Float64s(sortedHeadways)

	var cumulativeRankSum float64
	for idx, val := range sortedHeadways {
		rank := float64(idx + 1)
		cumulativeRankSum += rank * val
	}

	gini := 0.0
	if sumHeadway > 0 && fHeadwayCount > 1 {
		rawGini := (2.0*cumulativeRankSum)/(fHeadwayCount*sumHeadway) - (fHeadwayCount+1.0)/fHeadwayCount
		gini = rawGini * (fHeadwayCount / (fHeadwayCount - 1.0))
		if gini < 0 {
			gini = 0
		}
	}

	baseScore := 100.0 * math.Exp(-KappaMetricParam*cv)
	totalPenalties := (float64(bunchCount) * WeightBunchPenalty) + (float64(gapCount) * WeightGapPenalty)
	score := baseScore - totalPenalties

	if score < 0.0 {
		score = 0.0
	} else if score > 100.0 {
		score = 100.0
	}

	var status CorridorStatus
	if score >= 75.0 && bunchCount == 0 {
		status = StatusGood
	} else if (score >= 50.0 && bunchCount == 0) || (gapCount > 0 && bunchCount == 0) {
		status = StatusGaps
	} else {
		status = StatusDelayed
	}

	return &CorridorHealthResult{
		RouteID:             routeID,
		VehicleCount:        n,
		ScheduledHeadwaySec: schedHeadwaySec,
		MeanHeadwaySec:      meanHeadway,
		HeadwayStdDevSec:    stdDev,
		CoefficientOfVar:    cv,
		GiniCoefficient:     gini,
		BunchingEventCount:  bunchCount,
		ServiceGapCount:     gapCount,
		CorridorHealthScore: math.Round(score*10.0) / 10.0,
		Status:              status,
		Classifications:     classifications,
	}, nil
}
```

---

## 5. GeoJSON Specification for Route Vehicle Collections

```json
{
  "type": "FeatureCollection",
  "metadata": {
    "route_id": "METRO_LINE_101",
    "route_short_name": "101",
    "timestamp": 1774958400,
    "corridor_health_score": 42.5,
    "corridor_status": "Delayed",
    "coefficient_of_variation": 0.584,
    "active_bunching_count": 2,
    "active_gap_count": 1
  },
  "features": [
    {
      "type": "Feature",
      "id": "veh_bus_9021",
      "geometry": {
        "type": "Point",
        "coordinates": [-122.419416, 37.774929]
      },
      "properties": {
        "feature_class": "vehicle_marker",
        "vehicle_id": "9021",
        "trip_id": "trip_9920194A",
        "bearing": 45.0,
        "speed_mps": 0.8,
        "delay_sec": 420,
        "is_target": true,
        "is_bunched": true,
        "is_service_gap": false,
        "curvilinear_offset_m": 4120.5,
        "headway_sec": 110.0,
        "scheduled_headway_sec": 600.0,
        "status_color": "#D32F2F",
        "halo_color": "#FFCDD2"
      }
    },
    {
      "type": "Feature",
      "id": "veh_bus_9022",
      "geometry": {
        "type": "Point",
        "coordinates": [-122.418210, 37.775820]
      },
      "properties": {
        "feature_class": "vehicle_marker",
        "vehicle_id": "9022",
        "trip_id": "trip_9920195A",
        "bearing": 44.5,
        "speed_mps": 11.2,
        "delay_sec": -60,
        "is_target": false,
        "is_bunched": true,
        "is_service_gap": false,
        "curvilinear_offset_m": 4280.0,
        "headway_sec": 13.3,
        "scheduled_headway_sec": 600.0,
        "status_color": "#D32F2F",
        "halo_color": "#FFCDD2"
      }
    },
    {
      "type": "Feature",
      "id": "segment_bunch_9021_9022",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [-122.419416, 37.774929],
          [-122.418813, 37.775375],
          [-122.418210, 37.775820]
        ]
      },
      "properties": {
        "feature_class": "bunching_segment",
        "severity": "critical",
        "trailing_vehicle_id": "9021",
        "leading_vehicle_id": "9022",
        "segment_length_m": 159.5,
        "headway_compression_ratio": 0.022,
        "line_color": "#B71C1C",
        "casing_color": "#FFEBEE"
      }
    }
  ]
}
```

---

## 6. MapLibre Native Layer Controller (Swift)

```swift
import Foundation
import MapLibre

public final class CorridorPulseMapController: NSObject, MLNMapViewDelegate {
    
    private weak var mapView: MLNMapView?
    
    private enum Config {
        static let vehicleSourceID = "corridor-vehicles-source"
        static let bunchingSegmentsSourceID = "corridor-bunching-segments-source"
        
        static let bunchingCasingLayerID = "corridor-bunching-casing-layer"
        static let bunchingLineLayerID = "corridor-bunching-line-layer"
        
        static let vehicleTargetHaloLayerID = "vehicle-target-halo-layer"
        static let vehicleCircleBaseLayerID = "vehicle-circle-base-layer"
        static let vehicleDirectionArrowLayerID = "vehicle-direction-arrow-layer"
        static let vehicleLabelLayerID = "vehicle-label-layer"
    }

    public init(mapView: MLNMapView) {
        self.mapView = mapView
        super.init()
        self.mapView?.delegate = self
    }

    public func configureCorridorLayers(in style: MLNStyle) {
        setupDynamicSources(in: style)
        setupBunchingSegmentLayers(in: style)
        setupVehicleTokenLayers(in: style)
    }

    private func setupDynamicSources(in style: MLNStyle) {
        let emptyCollection = MLNShapeCollectionFeature(shapes: [])
        
        let bunchingSource = MLNShapeSource(
            identifier: Config.bunchingSegmentsSourceID,
            shape: emptyCollection,
            options: nil
        )
        style.addSource(bunchingSource)
        
        let vehicleSource = MLNShapeSource(
            identifier: Config.vehicleSourceID,
            shape: emptyCollection,
            options: nil
        )
        style.addSource(vehicleSource)
    }

    private func setupBunchingSegmentLayers(in style: MLNStyle) {
        guard let bunchSource = style.source(withIdentifier: Config.bunchingSegmentsSourceID) else { return }

        let segmentFilter = NSPredicate(format: "feature_class == 'bunching_segment'")

        let casingLayer = MLNLineStyleLayer(identifier: Config.bunchingCasingLayerID, source: bunchSource)
        casingLayer.predicate = segmentFilter
        casingLayer.lineJoin = NSExpression(forConstantValue: "round")
        casingLayer.lineCap = NSExpression(forConstantValue: "round")
        casingLayer.lineColor = NSExpression(forKeyPath: "casing_color")
        casingLayer.lineOpacity = NSExpression(forConstantValue: 0.85)
        
        casingLayer.lineWidth = NSExpression(
            forMLNInterpolating: NSExpression.zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                11: 4.0,
                14: 8.0,
                17: 16.0
            ])
        )
        style.addLayer(casingLayer)

        let lineLayer = MLNLineStyleLayer(identifier: Config.bunchingLineLayerID, source: bunchSource)
        lineLayer.predicate = segmentFilter
        lineLayer.lineJoin = NSExpression(forConstantValue: "round")
        lineLayer.lineCap = NSExpression(forConstantValue: "round")
        lineLayer.lineColor = NSExpression(forKeyPath: "line_color")
        
        lineLayer.lineWidth = NSExpression(
            forMLNInterpolating: NSExpression.zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                11: 2.0,
                14: 4.0,
                17: 8.0
            ])
        )
        lineLayer.lineDashPattern = NSExpression(forConstantValue: [1.5, 0.75])
        style.addLayer(lineLayer)
    }

    private func setupVehicleTokenLayers(in style: MLNStyle) {
        guard let vehicleSource = style.source(withIdentifier: Config.vehicleSourceID) else { return }

        let vehicleFilter = NSPredicate(format: "feature_class == 'vehicle_marker'")

        let haloLayer = MLNCircleStyleLayer(identifier: Config.vehicleTargetHaloLayerID, source: vehicleSource)
        haloLayer.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            vehicleFilter,
            NSPredicate(format: "is_target == YES")
        ])
        haloLayer.circlePitchAlignment = NSExpression(forConstantValue: "map")
        haloLayer.circleColor = NSExpression(forKeyPath: "halo_color")
        haloLayer.circleOpacity = NSExpression(forConstantValue: 0.60)
        haloLayer.circleRadius = NSExpression(
            forMLNInterpolating: NSExpression.zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                11: 12.0,
                14: 20.0,
                17: 34.0
            ])
        )
        style.addLayer(haloLayer)

        let circleLayer = MLNCircleStyleLayer(identifier: Config.vehicleCircleBaseLayerID, source: vehicleSource)
        circleLayer.predicate = vehicleFilter
        circleLayer.circlePitchAlignment = NSExpression(forConstantValue: "map")
        circleLayer.circleColor = NSExpression(forKeyPath: "status_color")
        circleLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        circleLayer.circleStrokeWidth = NSExpression(
            forMLNInterpolating: NSExpression.zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                10: 1.0,
                14: 2.0,
                17: 3.0
            ])
        )
        circleLayer.circleRadius = NSExpression(
            forMLNInterpolating: NSExpression.zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                10: 4.0,
                13: 7.0,
                16: 12.0
            ])
        )
        style.addLayer(circleLayer)

        let directionLayer = MLNSymbolStyleLayer(identifier: Config.vehicleDirectionArrowLayerID, source: vehicleSource)
        directionLayer.predicate = vehicleFilter
        directionLayer.iconImageName = NSExpression(forConstantValue: "transit-bearing-arrow")
        directionLayer.iconRotationAlignment = NSExpression(forConstantValue: "map")
        directionLayer.iconRotation = NSExpression(forKeyPath: "bearing")
        directionLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        directionLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        directionLayer.iconScale = NSExpression(
            forMLNInterpolating: NSExpression.zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                11: 0.4,
                14: 0.7,
                17: 1.0
            ])
        )
        style.addLayer(directionLayer)

        let labelLayer = MLNSymbolStyleLayer(identifier: Config.vehicleLabelLayerID, source: vehicleSource)
        labelLayer.predicate = vehicleFilter
        labelLayer.minimumZoomLevel = 13.5
        labelLayer.text = NSExpression(format: "vehicle_id")
        labelLayer.textFontSize = NSExpression(forConstantValue: 11.0)
        labelLayer.textTranslation = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 14)))
        labelLayer.textColor = NSExpression(forConstantValue: UIColor.black)
        labelLayer.textHaloColor = NSExpression(forConstantValue: UIColor.white)
        labelLayer.textHaloWidth = NSExpression(forConstantValue: 1.5)
        labelLayer.textAllowsOverlap = NSExpression(forConstantValue: false)
        style.addLayer(labelLayer)
    }

    public func updateTelemetry(geoJsonData: Data) {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self,
                  let style = self.mapView?.style else { return }

            do {
                let shape = try MLNShape(data: geoJsonData, encoding: String.Encoding.utf8.rawValue)
                
                DispatchQueue.main.async {
                    if let vehicleSource = style.source(withIdentifier: Config.vehicleSourceID) as? MLNShapeSource {
                        vehicleSource.shape = shape
                    }
                }
            } catch {
                // Ignore malformed network payloads and maintain current frame state
            }
        }
    }
}
```

---

## 7. Operational Latency Budget ($< 1.0\text{ ms}$)

| Processing Pipeline Stage | Target Compute Budget | Primary Implementation Strategy |
|:---|:---:|:---|
| **Telemetry Ingestion & Decode** | $\approx 150\,\mu\text{s}$ | Zero-copy Protocol Buffer unmarshaling from GTFS-RT streaming sockets. |
| **Linear Referencing Snap (LRS)** | $\approx 250\,\mu\text{s}$ | Curvilinear distance projection along spatial index trees of route geometry. |
| **Dispersion Metrics Engine** | $\approx 80\,\mu\text{s}$ | Welford’s single-pass algorithm for $\mu_h$ and $\sigma_h^2$, bypassing dynamic heap allocation. |
| **Health Scoring & Tier Resolution** | $\approx 20\,\mu\text{s}$ | Fixed-parameter exponential evaluation and discrete penalty thresholding. |
| **Buffer Headroom** | $\approx 500\,\mu\text{s}$ | Absorbs system interrupts to guarantee $<1.0\,\text{ms}$ execution latency per corridor. |

### Tri-Tier Operational Control Strategy
- **Tier 1 (Good, $S_{\text{corridor}} \ge 75$, LOS A–B):** Fleet spacing remains uniform. Passive monitoring without intervention.
- **Tier 2 (Gaps, $50 \le S_{\text{corridor}} < 75$, LOS C–D):** Significant headway dispersion develops without physical platooning. Alert operators and transmit virtual pacing targets to leading vehicles.
- **Tier 3 (Delayed, $S_{\text{corridor}} < 50$ or $N_{\text{bunch}} > 0$, LOS E–F):** Active platoons compromise service regularity. Enact automated dynamic holding on trailing bunched vehicles, TSP extensions for lead vehicles, and skip-stop boarding protocols.
