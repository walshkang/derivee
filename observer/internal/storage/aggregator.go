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
		SELECT route_id, stop_id, delay_seconds, observed_at 
		FROM stop_events 
		WHERE observed_at > ?
	`, time.Now().AddDate(0, 0, -30).Unix())
	if err != nil {
		return err
	}
	defer rows.Close()

	// Group by: Route -> Stop -> DayOfWeek -> Hour -> []delays
	type groupKey struct {
		RouteID string
		StopID  string
		DoW     int
		Hour    int
	}

	grouped := make(map[groupKey][]int)

	nyc, _ := time.LoadLocation("America/New_York")
	if nyc == nil {
		nyc = time.Local
	}

	for rows.Next() {
		var routeID, stopID string
		var delay int
		var observedAt int64

		if err := rows.Scan(&routeID, &stopID, &delay, &observedAt); err != nil {
			continue
		}

		t := time.Unix(observedAt, 0).In(nyc)
		key := groupKey{
			RouteID: routeID,
			StopID:  stopID,
			DoW:     int(t.Weekday()),
			Hour:    t.Hour(),
		}
		grouped[key] = append(grouped[key], delay)
	}

	// 2. Compute percentiles & on-time pct and save
	tx, err := d.db.Begin()
	if err != nil {
		return err
	}

	stmt, err := tx.Prepare(`
		INSERT INTO stop_reliability_hourly (route_id, stop_id, hour_of_day, day_of_week, median_delay_sec, p90_delay_sec, ewt_seconds, on_time_pct, sample_count)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(route_id, stop_id, hour_of_day, day_of_week) DO UPDATE SET
			median_delay_sec = excluded.median_delay_sec,
			p90_delay_sec = excluded.p90_delay_sec,
			ewt_seconds = excluded.ewt_seconds,
			on_time_pct = excluded.on_time_pct,
			sample_count = excluded.sample_count;
	`)
	if err != nil {
		tx.Rollback()
		return err
	}
	defer stmt.Close()

	for key, delays := range grouped {
		if len(delays) == 0 {
			continue
		}

		sort.Ints(delays)
		count := len(delays)

		median := delays[count/2]
		p90Idx := int(math.Floor(float64(count) * 0.90))
		if p90Idx >= count {
			p90Idx = count - 1
		}
		p90 := delays[p90Idx]

		onTimeCount := 0
		for _, d := range delays {
			// On time: <= 1 min early (-60s), <= 5 min late (300s)
			if d >= -60 && d <= 300 {
				onTimeCount++
			}
		}
		onTimePct := float64(onTimeCount) / float64(count) * 100.0

		// EWT is complex to compute purely from delays without knowing headways. 
		// For MVP, we'll store a mock EWT or 0, focusing on schedule adherence.
		ewt := 0.0

		_, err = stmt.Exec(key.RouteID, key.StopID, key.Hour, key.DoW, median, p90, ewt, onTimePct, count)
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
