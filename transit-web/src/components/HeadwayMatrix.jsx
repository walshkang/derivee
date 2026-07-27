import React from 'react';
import './HeadwayMatrix.css';

export default function HeadwayMatrix({ data }) {
  // data is an array of objects: { hour: '12', arrivals: [{ minute: '03', status: 'on-time' }, ...] }
  
  if (!data || data.length === 0) {
    return <div className="matrix-empty">No historical data available</div>;
  }

  return (
    <div className="headway-matrix">
      {data.map((row) => (
        <div key={row.hour} className="matrix-row">
          <div className="matrix-hour">{row.hour}</div>
          <div className="matrix-minutes">
            {row.arrivals.map((arr, idx) => (
              <span key={idx} className={`matrix-minute headway-${arr.status}`}>
                {arr.minute}
              </span>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
