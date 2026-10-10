import { useEffect, useState } from 'preact/hooks';

interface Arrival {
  route_id: string;
  route_short_name?: string;
  headsign?: string;
  destination?: string;
  arrival_time?: number;
  minutes_away?: number;
  is_realtime: boolean;
}

interface StationArrivalsProps {
  stationId: number;
  stationName: string;
  onClose: () => void;
}

export function StationArrivals({ stationId, stationName, onClose }: StationArrivalsProps) {
  const [arrivals, setArrivals] = useState<Arrival[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);

    fetch(`/api/realtime/arrivals?stop_id=${stationId}`)
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((data) => {
        if (cancelled) return;
        // API returns { arrivals: [...] } or array directly
        const list = Array.isArray(data) ? data : data.arrivals || [];
        setArrivals(list);
        setLoading(false);
      })
      .catch((err) => {
        if (cancelled) return;
        setError(err.message || 'Failed to load arrivals');
        setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [stationId]);

  return (
    <div className="station-arrivals-sheet">
      <div className="station-arrivals-header">
        <h3>{stationName}</h3>
        <button type="button" className="station-arrivals-close" onClick={onClose} aria-label="Close">
          ✕
        </button>
      </div>

      {loading && (
        <div className="station-arrivals-loading">
          <span className="loading-spinner" /> Loading arrivals…
        </div>
      )}

      {error && (
        <div className="station-arrivals-error">
          Could not load arrivals: {error}
        </div>
      )}

      {!loading && !error && arrivals && arrivals.length === 0 && (
        <div className="station-arrivals-empty">
          No upcoming arrivals.
        </div>
      )}

      {!loading && !error && arrivals && arrivals.length > 0 && (
        <ul className="station-arrivals-list">
          {arrivals.slice(0, 10).map((a, i) => (
            <li key={i} className="station-arrival-item">
              <span className={`arrival-live-dot ${a.is_realtime ? 'live' : 'scheduled'}`}
                title={a.is_realtime ? 'Live' : 'Scheduled'} />
              <span className="arrival-route">{a.route_short_name || a.route_id}</span>
              <span className="arrival-dest">{a.headsign || a.destination || ''}</span>
              <span className="arrival-time">
                {a.minutes_away !== undefined ? `${a.minutes_away} min` : '—'}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
