package gtfs

import "time"

// Agency represents a GTFS agency record
type Agency struct {
	AgencyID       string
	AgencyName     string
	AgencyURL      string
	AgencyTimezone string
}

// Route represents a GTFS route record
type Route struct {
	RouteID        string
	AgencyID       string
	RouteShortName string
	RouteLongName  string
	RouteType      int
	RouteColor     string
	RouteTextColor string
}

// Stop represents a GTFS stop record
type Stop struct {
	StopID             string
	StopName           string
	StopLat            float64
	StopLon            float64
	LocationType       int
	ParentStation      string
	PlatformCode       string
	WheelchairBoarding int
}

// Trip represents a GTFS trip record
type Trip struct {
	TripID        string
	RouteID       string
	ServiceID     string
	TripHeadsign  string
	DirectionID   int
	ShapeID       string
	ExactTimes    int
	HeadwaySecs   int
}

// StopTime represents a GTFS stop_time record
type StopTime struct {
	TripID            string
	StopID            string
	StopSequence      int
	ArrivalTimeSec    int
	DepartureTimeSec  int
	Timepoint         int
	ShapeDistTraveled float64
}

// Calendar represents a GTFS calendar record
type Calendar struct {
	ServiceID string
	Monday    bool
	Tuesday   bool
	Wednesday bool
	Thursday  bool
	Friday    bool
	Saturday  bool
	Sunday    bool
	StartDate string // YYYYMMDD
	EndDate   string // YYYYMMDD
}

// CalendarDate represents a GTFS calendar_dates record
type CalendarDate struct {
	ServiceID     string
	Date          string // YYYYMMDD
	ExceptionType int    // 1 = added, 2 = removed
}

// Frequency represents a GTFS frequencies record
type Frequency struct {
	TripID       string
	StartTimeSec int
	EndTimeSec   int
	HeadwaySecs  int
	ExactTimes   int
}

// ShapePoint represents a point in a GTFS shape polyline
type ShapePoint struct {
	ShapeID           string
	ShapePtLat        float64
	ShapePtLon        float64
	ShapePtSequence   int
	ShapeDistTraveled float64
}

// Modal Class constants
const (
	ModalClassSubway = 0 // Heavy Rail / Subway / Metro
	ModalClassLRT    = 1 // Light Rail / Tram / Streetcar
	ModalClassBus    = 2 // BRT / Bus / Trolleybus
	ModalClassFerry  = 3 // Maritime Ferry
)

// ResolveModalClass normalizes standard and Extended GTFS (HVT) route types into 4 core modal classes
func ResolveModalClass(routeType int) int {
	switch routeType {
	case 0, 900, 901, 904: // Tram / Streetcar / Light Rail
		return ModalClassLRT
	case 1, 2, 401, 402, 405: // Subway / Heavy Rail / Metro / Monorail
		return ModalClassSubway
	case 3, 5, 11, 700, 702, 800: // Bus / Cable Car / Trolleybus
		return ModalClassBus
	case 4, 1000, 1200: // Maritime Ferry
		return ModalClassFerry
	default:
		if routeType >= 100 && routeType < 200 { // Railway / Commuter Rail
			return ModalClassSubway
		} else if routeType >= 400 && routeType < 500 { // Metro / Underground
			return ModalClassSubway
		} else if routeType >= 700 && routeType < 900 { // Bus / Coach / Trolleybus
			return ModalClassBus
		} else if routeType >= 900 && routeType < 1000 { // Tram / LRT
			return ModalClassLRT
		} else if routeType >= 1000 && routeType < 1300 { // Water / Ferry
			return ModalClassFerry
		}
		return ModalClassSubway
	}
}

// ScheduledHourlyPattern represents a compacted hourly schedule pattern row
type ScheduledHourlyPattern struct {
	StopID             string
	RouteID            string
	DirectionID        int
	HourOfDay          int    // 0..23
	ServiceMask        uint16 // 14-day bitmask (bit 7 = anchor date T0)
	BaselineDaysOfWeek uint8  // 7-bit fallback mask (bit 0 = Sunday, bit 1 = Monday, etc.)
	MinuteOffsets      string // e.g. "04,16,28,40,52"
	Headsign           string
}

// StopResolution represents an entry in the pre-compiled reflexive transitive closure
type StopResolution struct {
	ParentStopID       string
	ChildStopID        string
	IsParent           int // 0 or 1
	PlatformCode       string
	WheelchairBoarding int
}

// Dataset represents a parsed in-memory GTFS dataset
type Dataset struct {
	Agencies        map[string]Agency
	Routes          map[string]Route
	Stops           map[string]Stop
	Trips           map[string]Trip
	StopTimes       map[string][]StopTime // Keyed by TripID, sorted by StopSequence
	Shapes          map[string][]ShapePoint // Keyed by ShapeID, sorted by ShapePtSequence
	Calendars       map[string]Calendar
	CalendarDates   map[string][]CalendarDate // Keyed by ServiceID
	Frequencies     map[string][]Frequency    // Keyed by TripID
	CompilationDate time.Time
}

// NewDataset creates an initialized Dataset
func NewDataset(compilationDate time.Time) *Dataset {
	return &Dataset{
		Agencies:        make(map[string]Agency),
		Routes:          make(map[string]Route),
		Stops:           make(map[string]Stop),
		Trips:           make(map[string]Trip),
		StopTimes:       make(map[string][]StopTime),
		Shapes:          make(map[string][]ShapePoint),
		Calendars:       make(map[string]Calendar),
		CalendarDates:   make(map[string][]CalendarDate),
		Frequencies:     make(map[string][]Frequency),
		CompilationDate: compilationDate,
	}
}
