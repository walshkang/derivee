package gtfs

import (
	"archive/zip"
	"bytes"
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

// ParseGTFSArchive parses a GTFS .zip archive from reader into a Dataset
func ParseGTFSArchive(r io.ReaderAt, size int64, compilationDate time.Time) (*Dataset, error) {
	zr, err := zip.NewReader(r, size)
	if err != nil {
		return nil, fmt.Errorf("failed to open zip reader: %w", err)
	}

	ds := NewDataset(compilationDate)

	for _, f := range zr.File {
		baseName := strings.ToLower(f.Name)
		if idx := strings.LastIndex(baseName, "/"); idx != -1 {
			baseName = baseName[idx+1:]
		}

		switch baseName {
		case "agency.txt":
			if err := parseAgencyFile(f, ds); err != nil {
				return nil, fmt.Errorf("error parsing agency.txt: %w", err)
			}
		case "routes.txt":
			if err := parseRoutesFile(f, ds); err != nil {
				return nil, fmt.Errorf("error parsing routes.txt: %w", err)
			}
		case "stops.txt":
			if err := parseStopsFile(f, ds); err != nil {
				return nil, fmt.Errorf("error parsing stops.txt: %w", err)
			}
		case "trips.txt":
			if err := parseTripsFile(f, ds); err != nil {
				return nil, fmt.Errorf("error parsing trips.txt: %w", err)
			}
		case "stop_times.txt":
			if err := parseStopTimesFile(f, ds); err != nil {
				return nil, fmt.Errorf("error parsing stop_times.txt: %w", err)
			}
		case "shapes.txt":
			if err := parseShapesFile(f, ds); err != nil {
				return nil, fmt.Errorf("error parsing shapes.txt: %w", err)
			}
		case "calendar.txt":
			if err := parseCalendarFile(f, ds); err != nil {
				return nil, fmt.Errorf("error parsing calendar.txt: %w", err)
			}
		case "calendar_dates.txt":
			if err := parseCalendarDatesFile(f, ds); err != nil {
				return nil, fmt.Errorf("error parsing calendar_dates.txt: %w", err)
			}
		case "frequencies.txt":
			if err := parseFrequenciesFile(f, ds); err != nil {
				return nil, fmt.Errorf("error parsing frequencies.txt: %w", err)
			}
		}
	}

	return ds, nil
}

// ParseGTFSFile parses a local GTFS .zip file
func ParseGTFSFile(filePath string, compilationDate time.Time) (*Dataset, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read GTFS file %s: %w", filePath, err)
	}
	return ParseGTFSArchive(bytes.NewReader(data), int64(len(data)), compilationDate)
}

func parseTime(t string) int {
	t = strings.TrimSpace(t)
	if t == "" {
		return -1
	}
	parts := strings.Split(t, ":")
	if len(parts) != 3 {
		return -1
	}
	h, err1 := strconv.Atoi(strings.TrimSpace(parts[0]))
	m, err2 := strconv.Atoi(strings.TrimSpace(parts[1]))
	s, err3 := strconv.Atoi(strings.TrimSpace(parts[2]))
	if err1 != nil || err2 != nil || err3 != nil {
		return -1
	}
	return h*3600 + m*60 + s
}

func parseAgencyFile(f *zip.File, ds *Dataset) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	reader := csv.NewReader(rc)
	reader.FieldsPerRecord = -1
	headers, err := reader.Read()
	if err != nil {
		return err
	}

	headerMap := make(map[string]int)
	for i, h := range headers {
		headerMap[strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))] = i
	}

	idIdx, hasID := headerMap["agency_id"]
	nameIdx, hasName := headerMap["agency_name"]
	urlIdx, hasURL := headerMap["agency_url"]
	tzIdx, hasTZ := headerMap["agency_timezone"]

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			continue
		}

		var id, name, url, tz string
		if hasID && idIdx < len(record) {
			id = strings.TrimSpace(record[idIdx])
		}
		if hasName && nameIdx < len(record) {
			name = strings.TrimSpace(record[nameIdx])
		}
		if hasURL && urlIdx < len(record) {
			url = strings.TrimSpace(record[urlIdx])
		}
		if hasTZ && tzIdx < len(record) {
			tz = strings.TrimSpace(record[tzIdx])
		}

		if id == "" {
			id = name
		}

		ds.Agencies[id] = Agency{
			AgencyID:       id,
			AgencyName:     name,
			AgencyURL:      url,
			AgencyTimezone: tz,
		}
	}
	return nil
}

func parseRoutesFile(f *zip.File, ds *Dataset) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	reader := csv.NewReader(rc)
	reader.FieldsPerRecord = -1
	headers, err := reader.Read()
	if err != nil {
		return err
	}

	headerMap := make(map[string]int)
	for i, h := range headers {
		headerMap[strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))] = i
	}

	idIdx, hasID := headerMap["route_id"]
	agencyIdx, hasAgency := headerMap["agency_id"]
	shortIdx, hasShort := headerMap["route_short_name"]
	longIdx, hasLong := headerMap["route_long_name"]
	typeIdx, hasType := headerMap["route_type"]
	colorIdx, hasColor := headerMap["route_color"]
	textColorIdx, hasTextColor := headerMap["route_text_color"]

	if !hasID {
		return fmt.Errorf("routes.txt missing route_id")
	}

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(record) <= idIdx {
			continue
		}

		routeID := strings.TrimSpace(record[idIdx])
		if routeID == "" {
			continue
		}

		var agencyID, shortName, longName, color, textColor string
		rType := 0

		if hasAgency && agencyIdx < len(record) {
			agencyID = strings.TrimSpace(record[agencyIdx])
		}
		if hasShort && shortIdx < len(record) {
			shortName = strings.TrimSpace(record[shortIdx])
		}
		if hasLong && longIdx < len(record) {
			longName = strings.TrimSpace(record[longIdx])
		}
		if hasType && typeIdx < len(record) {
			rType, _ = strconv.Atoi(strings.TrimSpace(record[typeIdx]))
		}
		if hasColor && colorIdx < len(record) {
			color = strings.TrimSpace(record[colorIdx])
		}
		if hasTextColor && textColorIdx < len(record) {
			textColor = strings.TrimSpace(record[textColorIdx])
		}

		if color != "" && !strings.HasPrefix(color, "#") {
			color = "#" + color
		}
		if textColor != "" && !strings.HasPrefix(textColor, "#") {
			textColor = "#" + textColor
		}

		ds.Routes[routeID] = Route{
			RouteID:        routeID,
			AgencyID:       agencyID,
			RouteShortName: shortName,
			RouteLongName:  longName,
			RouteType:      rType,
			RouteColor:     color,
			RouteTextColor: textColor,
		}
	}
	return nil
}

func parseStopsFile(f *zip.File, ds *Dataset) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	reader := csv.NewReader(rc)
	reader.FieldsPerRecord = -1
	headers, err := reader.Read()
	if err != nil {
		return err
	}

	headerMap := make(map[string]int)
	for i, h := range headers {
		headerMap[strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))] = i
	}

	idIdx, hasID := headerMap["stop_id"]
	nameIdx, hasName := headerMap["stop_name"]
	latIdx, hasLat := headerMap["stop_lat"]
	lonIdx, hasLon := headerMap["stop_lon"]
	locTypeIdx, hasLocType := headerMap["location_type"]
	parentIdx, hasParent := headerMap["parent_station"]
	platformIdx, hasPlatform := headerMap["platform_code"]
	wheelchairIdx, hasWheelchair := headerMap["wheelchair_boarding"]

	if !hasID {
		return fmt.Errorf("stops.txt missing stop_id")
	}

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(record) <= idIdx {
			continue
		}

		stopID := strings.TrimSpace(record[idIdx])
		if stopID == "" {
			continue
		}

		var stopName, parentStation, platformCode string
		var lat, lon float64
		locType := 0
		wheelchair := 0

		if hasName && nameIdx < len(record) {
			stopName = strings.TrimSpace(record[nameIdx])
		}
		if hasLat && latIdx < len(record) {
			lat, _ = strconv.ParseFloat(strings.TrimSpace(record[latIdx]), 64)
		}
		if hasLon && lonIdx < len(record) {
			lon, _ = strconv.ParseFloat(strings.TrimSpace(record[lonIdx]), 64)
		}
		if hasLocType && locTypeIdx < len(record) && strings.TrimSpace(record[locTypeIdx]) != "" {
			locType, _ = strconv.Atoi(strings.TrimSpace(record[locTypeIdx]))
		}
		if hasParent && parentIdx < len(record) {
			parentStation = strings.TrimSpace(record[parentIdx])
		}
		if hasPlatform && platformIdx < len(record) {
			platformCode = strings.TrimSpace(record[platformIdx])
		}
		if hasWheelchair && wheelchairIdx < len(record) && strings.TrimSpace(record[wheelchairIdx]) != "" {
			wheelchair, _ = strconv.Atoi(strings.TrimSpace(record[wheelchairIdx]))
		}

		ds.Stops[stopID] = Stop{
			StopID:             stopID,
			StopName:           stopName,
			StopLat:            lat,
			StopLon:            lon,
			LocationType:       locType,
			ParentStation:      parentStation,
			PlatformCode:       platformCode,
			WheelchairBoarding: wheelchair,
		}
	}
	return nil
}

func parseTripsFile(f *zip.File, ds *Dataset) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	reader := csv.NewReader(rc)
	reader.FieldsPerRecord = -1
	headers, err := reader.Read()
	if err != nil {
		return err
	}

	headerMap := make(map[string]int)
	for i, h := range headers {
		headerMap[strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))] = i
	}

	tripIDIdx, hasTripID := headerMap["trip_id"]
	routeIDIdx, hasRouteID := headerMap["route_id"]
	serviceIDIdx, hasServiceID := headerMap["service_id"]
	headsignIdx, hasHeadsign := headerMap["trip_headsign"]
	dirIdx, hasDir := headerMap["direction_id"]
	shapeIdx, hasShape := headerMap["shape_id"]

	if !hasTripID || !hasRouteID || !hasServiceID {
		return fmt.Errorf("trips.txt missing required columns")
	}

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(record) <= tripIDIdx {
			continue
		}

		tripID := strings.TrimSpace(record[tripIDIdx])
		if tripID == "" {
			continue
		}

		var routeID, serviceID, headsign, shapeID string
		dirID := 0

		if routeIDIdx < len(record) {
			routeID = strings.TrimSpace(record[routeIDIdx])
		}
		if serviceIDIdx < len(record) {
			serviceID = strings.TrimSpace(record[serviceIDIdx])
		}
		if hasHeadsign && headsignIdx < len(record) {
			headsign = strings.TrimSpace(record[headsignIdx])
		}
		if hasDir && dirIdx < len(record) && strings.TrimSpace(record[dirIdx]) != "" {
			dirID, _ = strconv.Atoi(strings.TrimSpace(record[dirIdx]))
		}
		if hasShape && shapeIdx < len(record) {
			shapeID = strings.TrimSpace(record[shapeIdx])
		}

		ds.Trips[tripID] = Trip{
			TripID:       tripID,
			RouteID:      routeID,
			ServiceID:    serviceID,
			TripHeadsign: headsign,
			DirectionID:  dirID,
			ShapeID:      shapeID,
		}
	}
	return nil
}

func parseStopTimesFile(f *zip.File, ds *Dataset) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	reader := csv.NewReader(rc)
	reader.FieldsPerRecord = -1
	headers, err := reader.Read()
	if err != nil {
		return err
	}

	headerMap := make(map[string]int)
	for i, h := range headers {
		headerMap[strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))] = i
	}

	tripIDIdx, hasTripID := headerMap["trip_id"]
	stopIDIdx, hasStopID := headerMap["stop_id"]
	seqIdx, hasSeq := headerMap["stop_sequence"]
	arrIdx, hasArr := headerMap["arrival_time"]
	depIdx, hasDep := headerMap["departure_time"]
	tpIdx, hasTP := headerMap["timepoint"]
	distIdx, hasDist := headerMap["shape_dist_traveled"]

	if !hasTripID || !hasStopID || !hasSeq {
		return fmt.Errorf("stop_times.txt missing required columns")
	}

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(record) <= tripIDIdx || len(record) <= stopIDIdx || len(record) <= seqIdx {
			continue
		}

		tripID := strings.TrimSpace(record[tripIDIdx])
		stopID := strings.TrimSpace(record[stopIDIdx])
		seq, _ := strconv.Atoi(strings.TrimSpace(record[seqIdx]))

		arrSec := -1
		if hasArr && arrIdx < len(record) {
			arrSec = parseTime(record[arrIdx])
		}
		depSec := -1
		if hasDep && depIdx < len(record) {
			depSec = parseTime(record[depIdx])
		}

		tp := 1
		if hasTP && tpIdx < len(record) && strings.TrimSpace(record[tpIdx]) != "" {
			tp, _ = strconv.Atoi(strings.TrimSpace(record[tpIdx]))
		}

		dist := -1.0
		if hasDist && distIdx < len(record) && strings.TrimSpace(record[distIdx]) != "" {
			dist, _ = strconv.ParseFloat(strings.TrimSpace(record[distIdx]), 64)
		}

		ds.StopTimes[tripID] = append(ds.StopTimes[tripID], StopTime{
			TripID:            tripID,
			StopID:            stopID,
			StopSequence:      seq,
			ArrivalTimeSec:    arrSec,
			DepartureTimeSec:  depSec,
			Timepoint:         tp,
			ShapeDistTraveled: dist,
		})
	}
	return nil
}

func parseCalendarFile(f *zip.File, ds *Dataset) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	reader := csv.NewReader(rc)
	reader.FieldsPerRecord = -1
	headers, err := reader.Read()
	if err != nil {
		return err
	}

	headerMap := make(map[string]int)
	for i, h := range headers {
		headerMap[strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))] = i
	}

	serviceIDIdx, hasServiceID := headerMap["service_id"]
	monIdx, hasMon := headerMap["monday"]
	tueIdx, hasTue := headerMap["tuesday"]
	wedIdx, hasWed := headerMap["wednesday"]
	thuIdx, hasThu := headerMap["thursday"]
	friIdx, hasFri := headerMap["friday"]
	satIdx, hasSat := headerMap["saturday"]
	sunIdx, hasSun := headerMap["sunday"]
	startIdx, hasStart := headerMap["start_date"]
	endIdx, hasEnd := headerMap["end_date"]

	if !hasServiceID {
		return fmt.Errorf("calendar.txt missing service_id")
	}

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(record) <= serviceIDIdx {
			continue
		}

		serviceID := strings.TrimSpace(record[serviceIDIdx])
		if serviceID == "" {
			continue
		}

		parseBool := func(idx int, has bool) bool {
			if !has || idx >= len(record) {
				return false
			}
			val := strings.TrimSpace(record[idx])
			return val == "1" || strings.ToLower(val) == "true"
		}

		var start, end string
		if hasStart && startIdx < len(record) {
			start = strings.TrimSpace(record[startIdx])
		}
		if hasEnd && endIdx < len(record) {
			end = strings.TrimSpace(record[endIdx])
		}

		ds.Calendars[serviceID] = Calendar{
			ServiceID: serviceID,
			Monday:    parseBool(monIdx, hasMon),
			Tuesday:   parseBool(tueIdx, hasTue),
			Wednesday: parseBool(wedIdx, hasWed),
			Thursday:  parseBool(thuIdx, hasThu),
			Friday:    parseBool(friIdx, hasFri),
			Saturday:  parseBool(satIdx, hasSat),
			Sunday:    parseBool(sunIdx, hasSun),
			StartDate: start,
			EndDate:   end,
		}
	}
	return nil
}

func parseCalendarDatesFile(f *zip.File, ds *Dataset) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	reader := csv.NewReader(rc)
	reader.FieldsPerRecord = -1
	headers, err := reader.Read()
	if err != nil {
		return err
	}

	headerMap := make(map[string]int)
	for i, h := range headers {
		headerMap[strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))] = i
	}

	serviceIDIdx, hasServiceID := headerMap["service_id"]
	dateIdx, hasDate := headerMap["date"]
	exIdx, hasEx := headerMap["exception_type"]

	if !hasServiceID || !hasDate || !hasEx {
		return fmt.Errorf("calendar_dates.txt missing required columns")
	}

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(record) <= serviceIDIdx || len(record) <= dateIdx || len(record) <= exIdx {
			continue
		}

		serviceID := strings.TrimSpace(record[serviceIDIdx])
		date := strings.TrimSpace(record[dateIdx])
		exType, _ := strconv.Atoi(strings.TrimSpace(record[exIdx]))

		ds.CalendarDates[serviceID] = append(ds.CalendarDates[serviceID], CalendarDate{
			ServiceID:     serviceID,
			Date:          date,
			ExceptionType: exType,
		})
	}
	return nil
}

func parseFrequenciesFile(f *zip.File, ds *Dataset) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	reader := csv.NewReader(rc)
	reader.FieldsPerRecord = -1
	headers, err := reader.Read()
	if err != nil {
		return err
	}

	headerMap := make(map[string]int)
	for i, h := range headers {
		headerMap[strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))] = i
	}

	tripIDIdx, hasTripID := headerMap["trip_id"]
	startIdx, hasStart := headerMap["start_time"]
	endIdx, hasEnd := headerMap["end_time"]
	headwayIdx, hasHeadway := headerMap["headway_secs"]
	exactIdx, hasExact := headerMap["exact_times"]

	if !hasTripID || !hasStart || !hasEnd || !hasHeadway {
		return fmt.Errorf("frequencies.txt missing required columns")
	}

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(record) <= tripIDIdx || len(record) <= startIdx || len(record) <= endIdx || len(record) <= headwayIdx {
			continue
		}

		tripID := strings.TrimSpace(record[tripIDIdx])
		startSec := parseTime(record[startIdx])
		endSec := parseTime(record[endIdx])
		headwaySec, _ := strconv.Atoi(strings.TrimSpace(record[headwayIdx]))
		exact := 0
		if hasExact && exactIdx < len(record) && strings.TrimSpace(record[exactIdx]) != "" {
			exact, _ = strconv.Atoi(strings.TrimSpace(record[exactIdx]))
		}

		ds.Frequencies[tripID] = append(ds.Frequencies[tripID], Frequency{
			TripID:       tripID,
			StartTimeSec: startSec,
			EndTimeSec:   endSec,
			HeadwaySecs:  headwaySec,
			ExactTimes:   exact,
		})
	}
	return nil
}

func parseShapesFile(f *zip.File, ds *Dataset) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	reader := csv.NewReader(rc)
	reader.FieldsPerRecord = -1
	headers, err := reader.Read()
	if err != nil {
		return err
	}

	headerMap := make(map[string]int)
	for i, h := range headers {
		headerMap[strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))] = i
	}

	shapeIDIdx, hasShapeID := headerMap["shape_id"]
	latIdx, hasLat := headerMap["shape_pt_lat"]
	lonIdx, hasLon := headerMap["shape_pt_lon"]
	seqIdx, hasSeq := headerMap["shape_pt_sequence"]
	distIdx, hasDist := headerMap["shape_dist_traveled"]

	if !hasShapeID || !hasLat || !hasLon || !hasSeq {
		return fmt.Errorf("shapes.txt missing required columns")
	}

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(record) <= shapeIDIdx || len(record) <= latIdx || len(record) <= lonIdx || len(record) <= seqIdx {
			continue
		}

		shapeID := strings.TrimSpace(record[shapeIDIdx])
		if shapeID == "" {
			continue
		}

		lat, err1 := strconv.ParseFloat(strings.TrimSpace(record[latIdx]), 64)
		lon, err2 := strconv.ParseFloat(strings.TrimSpace(record[lonIdx]), 64)
		seq, err3 := strconv.Atoi(strings.TrimSpace(record[seqIdx]))
		if err1 != nil || err2 != nil || err3 != nil {
			continue
		}

		var dist float64
		if hasDist && distIdx < len(record) && strings.TrimSpace(record[distIdx]) != "" {
			dist, _ = strconv.ParseFloat(strings.TrimSpace(record[distIdx]), 64)
		}

		ds.Shapes[shapeID] = append(ds.Shapes[shapeID], ShapePoint{
			ShapeID:           shapeID,
			ShapePtLat:        lat,
			ShapePtLon:        lon,
			ShapePtSequence:   seq,
			ShapeDistTraveled: dist,
		})
	}

	// Ensure all shape point slices are ordered by sequence
	for shapeID := range ds.Shapes {
		pts := ds.Shapes[shapeID]
		sort.Slice(pts, func(i, j int) bool {
			return pts[i].ShapePtSequence < pts[j].ShapePtSequence
		})
		ds.Shapes[shapeID] = pts
	}

	return nil
}

