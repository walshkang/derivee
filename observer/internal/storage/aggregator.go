package storage

import (
	"log"
	"math"
	"sort"
	"time"
)

// AggregateDailyStats computes hourly reliability percentiles from raw events
func (d *Database) AggregateDailyStats() error {
	log.Println("Aggregating daily stats...")

	// 1. Fetch raw events from the last 30 days
	rows, err := d.db.Query(`
		SELECT route_id, stop_id, direction_id, delay_seconds, actual_time, observed_at 
		FROM stop_events 
		WHERE observed_at > ?
	`, time.Now().AddDate(0, 0, -30).Unix())
	if err != nil {
		return err
	}
	defer rows.Close()

	// Group by: Route -> Stop -> Direction -> DayOfWeek -> Hour -> []EventData
	type groupKey struct {
		RouteID     string
		StopID      string
		DirectionID uint32
		DoW         int
		Hour        int
	}
	
	type EventData struct {
		Delay      int
		ActualTime int64
	}

	grouped := make(map[groupKey][]EventData)

	nyc, _ := time.LoadLocation("America/New_York")
	if nyc == nil {
		nyc = time.Local
	}

	for rows.Next() {
		var routeID, stopID string
		var directionID uint32
		var delay int
		var actualTime int64
		var observedAt int64

		if err := rows.Scan(&routeID, &stopID, &directionID, &delay, &actualTime, &observedAt); err != nil {
			continue
		}

		t := time.Unix(observedAt, 0).In(nyc)
		key := groupKey{
			RouteID:     routeID,
			StopID:      stopID,
			DirectionID: directionID,
			DoW:         int(t.Weekday()),
			Hour:        t.Hour(),
		}
		grouped[key] = append(grouped[key], EventData{
			Delay:      delay,
			ActualTime: actualTime,
		})
	}

	// 2. Compute percentiles & on-time pct and save
	tx, err := d.db.Begin()
	if err != nil {
		return err
	}

	stmt, err := tx.Prepare(`
		INSERT INTO stop_reliability_hourly (route_id, stop_id, direction_id, hour_of_day, day_of_week, median_delay_sec, p90_delay_sec, median_headway_sec, headway_stddev_sec, ewt_seconds, on_time_pct, sample_count)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(route_id, stop_id, direction_id, hour_of_day, day_of_week) DO UPDATE SET
			median_delay_sec = excluded.median_delay_sec,
			p90_delay_sec = excluded.p90_delay_sec,
			median_headway_sec = excluded.median_headway_sec,
			headway_stddev_sec = excluded.headway_stddev_sec,
			ewt_seconds = excluded.ewt_seconds,
			on_time_pct = excluded.on_time_pct,
			sample_count = excluded.sample_count;
	`)
	if err != nil {
		tx.Rollback()
		return err
	}
	defer stmt.Close()

	for key, events := range grouped {
		if len(events) == 0 {
			continue
		}

		// Sort by actual time to compute headways
		sort.Slice(events, func(i, j int) bool {
			return events[i].ActualTime < events[j].ActualTime
		})

		var headways []int
		for i := 1; i < len(events); i++ {
			hw := events[i].ActualTime - events[i-1].ActualTime
			if hw > 60 && hw < 7200 { // valid headway between 1 min and 2 hours
				headways = append(headways, int(hw))
			}
		}

		medianHeadway := 0
		headwayStdDev := 0.0
		ewt := 0.0

		if len(headways) > 0 {
			sort.Ints(headways)
			medianHeadway = headways[len(headways)/2]

			sum := 0.0
			for _, h := range headways {
				sum += float64(h)
			}
			meanHeadway := sum / float64(len(headways))

			varSum := 0.0
			for _, h := range headways {
				diff := float64(h) - meanHeadway
				varSum += diff * diff
			}
			variance := varSum / float64(len(headways))
			headwayStdDev = math.Sqrt(variance)

			if meanHeadway > 0 {
				ewt = variance / (2 * meanHeadway)
			}
		}

		count := len(events)
		delays := make([]int, count)
		onTimeCount := 0
		for i, e := range events {
			delays[i] = e.Delay
			if e.Delay >= -60 && e.Delay <= 300 {
				onTimeCount++
			}
		}
		sort.Ints(delays)

		medianDelay := delays[count/2]
		p90Idx := int(math.Floor(float64(count) * 0.90))
		if p90Idx >= count {
			p90Idx = count - 1
		}
		p90Delay := delays[p90Idx]
		onTimePct := float64(onTimeCount) / float64(count) * 100.0

		_, err = stmt.Exec(key.RouteID, key.StopID, key.DirectionID, key.Hour, key.DoW, medianDelay, p90Delay, medianHeadway, int(headwayStdDev), ewt, onTimePct, count)
		if err != nil {
			log.Printf("Failed to insert aggregated stat for %v: %v", key, err)
		}
	}

	err = tx.Commit()
	if err != nil {
		return err
	}

	// 3. Truncate old events to save space
	_, err = d.db.Exec(`DELETE FROM stop_events WHERE observed_at <= ?`, time.Now().AddDate(0, 0, -30).Unix())
	return err
}
