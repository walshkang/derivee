package gtfs

import (
	"fmt"
	"time"
)

// CalendarResolver computes service masks and baseline day-of-week fallbacks
type CalendarResolver struct {
	AnchorDate    time.Time
	Calendars     map[string]Calendar
	CalendarDates map[string]map[string]int // serviceID -> dateStr (YYYYMMDD) -> exceptionType (1=add, 2=remove)
}

// NewCalendarResolver creates a new resolver centered at anchorDate
func NewCalendarResolver(anchorDate time.Time, calendars map[string]Calendar, calendarDates map[string][]CalendarDate) *CalendarResolver {
	dateMap := make(map[string]map[string]int)
	for serviceID, dates := range calendarDates {
		if _, ok := dateMap[serviceID]; !ok {
			dateMap[serviceID] = make(map[string]int)
		}
		for _, cd := range dates {
			dateMap[serviceID][cd.Date] = cd.ExceptionType
		}
	}

	return &CalendarResolver{
		AnchorDate:    anchorDate.UTC().Truncate(24 * time.Hour),
		Calendars:     calendars,
		CalendarDates: dateMap,
	}
}

// ComputeServiceMask calculates the 14-day uint16 bitmask for a given serviceID across [AnchorDate - 7d, AnchorDate + 6d]
// Bit 7 corresponds to AnchorDate (k=7).
func (cr *CalendarResolver) ComputeServiceMask(serviceID string) uint16 {
	var mask uint16 = 0

	for k := 0; k < 14; k++ {
		dayOffset := k - 7
		day := cr.AnchorDate.AddDate(0, 0, dayOffset)
		if cr.IsServiceActiveOnDate(serviceID, day) {
			mask |= (1 << k)
		}
	}

	return mask
}

// IsServiceActiveOnDate determines if serviceID is active on a specific calendar day
func (cr *CalendarResolver) IsServiceActiveOnDate(serviceID string, day time.Time) bool {
	dateStr := fmt.Sprintf("%04d%02d%02d", day.Year(), day.Month(), day.Day())

	// 1. Check calendar_dates exceptions first (highest priority)
	if exceptions, ok := cr.CalendarDates[serviceID]; ok {
		if exType, found := exceptions[dateStr]; found {
			if exType == 1 {
				return true
			} else if exType == 2 {
				return false
			}
		}
	}

	// 2. Check calendar regular pattern
	if cal, ok := cr.Calendars[serviceID]; ok {
		if cal.StartDate != "" && cal.EndDate != "" {
			if dateStr < cal.StartDate || dateStr > cal.EndDate {
				return false
			}
		}

		switch day.Weekday() {
		case time.Sunday:
			return cal.Sunday
		case time.Monday:
			return cal.Monday
		case time.Tuesday:
			return cal.Tuesday
		case time.Wednesday:
			return cal.Wednesday
		case time.Thursday:
			return cal.Thursday
		case time.Friday:
			return cal.Friday
		case time.Saturday:
			return cal.Saturday
		}
	}

	return false
}

// ComputeBaselineDaysOfWeek calculates the 7-bit uint8 fallback mask (bit 0 = Sun, bit 1 = Mon, ..., bit 6 = Sat)
func (cr *CalendarResolver) ComputeBaselineDaysOfWeek(serviceID string) uint8 {
	var mask uint8 = 0

	if cal, ok := cr.Calendars[serviceID]; ok {
		if cal.Sunday {
			mask |= (1 << 0)
		}
		if cal.Monday {
			mask |= (1 << 1)
		}
		if cal.Tuesday {
			mask |= (1 << 2)
		}
		if cal.Wednesday {
			mask |= (1 << 3)
		}
		if cal.Thursday {
			mask |= (1 << 4)
		}
		if cal.Friday {
			mask |= (1 << 5)
		}
		if cal.Saturday {
			mask |= (1 << 6)
		}
		return mask
	}

	// If calendar.txt is absent and only calendar_dates.txt is present, synthesize baseline from the 14-day window
	for k := 0; k < 14; k++ {
		day := cr.AnchorDate.AddDate(0, 0, k-7)
		if cr.IsServiceActiveOnDate(serviceID, day) {
			mask |= (1 << uint(day.Weekday()))
		}
	}

	return mask
}

// ShiftServiceMask shifts a 14-day service mask by dayShift days (used for trips departing past midnight, e.g. >= 24h)
func ShiftServiceMask(mask uint16, dayShift int) uint16 {
	if dayShift == 0 {
		return mask
	}
	if dayShift > 0 {
		return (mask << dayShift) & 0x3FFF // Keep 14 bits (0..13)
	}
	return (mask >> (-dayShift)) & 0x3FFF
}
