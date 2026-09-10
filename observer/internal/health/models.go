package health

// Mathematical thresholds and weighting parameters defined in Research Doc 19.
const (
	// BunchingThresholdFactor defines the critical headway fraction below which
	// a trailing vehicle is bunched (TCQSM alpha = 0.25).
	BunchingThresholdFactor = 0.25

	// ServiceGapThresholdFactor defines the critical headway factor above which
	// a severe passenger queue accumulation occurs (TCQSM beta = 1.75).
	ServiceGapThresholdFactor = 1.75

	// KappaMetricParam scales exponential decay of the health score relative to CV_h.
	KappaMetricParam = 1.60

	// WeightBunchPenalty is deducted per bunched vehicle pair.
	WeightBunchPenalty = 15.0

	// WeightGapPenalty is deducted per service gap.
	WeightGapPenalty = 10.0

	// DefaultNominalSpeedMPS is the fallback speed (~26.8 mph / 12.0 m/s) when
	// vehicle speeds are unavailable or near zero (dwelling/stopped).
	DefaultNominalSpeedMPS = 12.0

	// StoppedSpeedThresholdMPS is the speed below which a vehicle is considered dwelling.
	StoppedSpeedThresholdMPS = 2.5
)

// CorridorStatus classifies the health of an active transit corridor.
type CorridorStatus string

const (
	StatusGood    CorridorStatus = "Good"
	StatusGaps    CorridorStatus = "Gaps"
	StatusDelayed CorridorStatus = "Delayed"
)

// ActiveVehicleInput models a vehicle operating along a corridor.
type ActiveVehicleInput struct {
	VehicleID          string  `json:"vehicle_id"`
	TripID             string  `json:"trip_id,omitempty"`
	CurvilinearOffsetM float64 `json:"curvilinear_offset_m"`
	SpeedMetersPerSec  float64 `json:"speed_mps"`
	DelaySec           int64   `json:"delay_sec"`
	IsTargetVehicle    bool    `json:"is_target"`
	Bearing            float64 `json:"bearing"`
	Latitude           float64 `json:"latitude,omitempty"`
	Longitude          float64 `json:"longitude,omitempty"`
}

// VehicleClassification contains headway analysis for an individual vehicle.
type VehicleClassification struct {
	VehicleID        string  `json:"vehicle_id"`
	SpatialHeadwayM  float64 `json:"spatial_headway_m"`
	TemporalHeadway  float64 `json:"temporal_headway_sec"`
	IsBunched        bool    `json:"is_bunched"`
	IsServiceGap     bool    `json:"is_service_gap"`
	CompressionRatio float64 `json:"compression_ratio,omitempty"`
}

// CorridorHealthResult represents the aggregate regularity metrics for a corridor.
type CorridorHealthResult struct {
	RouteID             string                  `json:"route_id"`
	RouteShortName      string                  `json:"route_short_name,omitempty"`
	Timestamp           int64                   `json:"timestamp,omitempty"`
	VehicleCount        int                     `json:"vehicle_count"`
	ScheduledHeadwaySec float64                 `json:"scheduled_headway_sec"`
	MeanHeadwaySec      float64                 `json:"mean_headway_sec"`
	HeadwayStdDevSec    float64                 `json:"headway_std_dev_sec"`
	CoefficientOfVar    float64                 `json:"coefficient_of_variation"`
	GiniCoefficient     float64                 `json:"gini_coefficient"`
	ExpectedWaitTimeSec float64                 `json:"expected_wait_sec"`
	BunchingEventCount  int                     `json:"bunching_event_count"`
	ServiceGapCount     int                     `json:"service_gap_count"`
	CorridorHealthScore float64                 `json:"corridor_health_score"`
	Status              CorridorStatus          `json:"corridor_status"`
	Classifications     []VehicleClassification `json:"classifications"`
}
