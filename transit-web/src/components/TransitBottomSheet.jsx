import React from 'react';
import { Drawer } from 'vaul';
import Sparkline from './Sparkline';
import './TransitBottomSheet.css';

export default function TransitBottomSheet({ open, onOpenChange, stationName, sparklineData, liveArrivals, routeId }) {
  const getMinutesUntil = (unixSeconds) => {
    const diff = unixSeconds - Math.floor(Date.now() / 1000);
    if (diff <= 0) return 'Due';
    return `${Math.floor(diff / 60)} min`;
  };

  return (
    <Drawer.Root open={open} onOpenChange={onOpenChange}>
      <Drawer.Portal>
        <Drawer.Overlay className="drawer-overlay" />
        <Drawer.Content className="drawer-content glass">
          <div className="drawer-handle" />
          <div className="drawer-body">
            <Drawer.Title className="drawer-title">{stationName || 'Transit Node'}</Drawer.Title>
            
            <div className="drawer-arrivals-list">
              {liveArrivals && liveArrivals.length > 0 ? (
                liveArrivals.map((arr, idx) => (
                  <div key={idx} className="drawer-arrival-item">
                    <span className="arrival-route">{arr.routeId}</span>
                    <span className="arrival-direction">{arr.direction || 'Expected'}</span>
                    <span className="arrival-time">{getMinutesUntil(arr.arrivalTime)}</span>
                  </div>
                ))
              ) : (
                <div className="arrival-empty">No real-time arrivals available</div>
              )}
            </div>

            <p className="drawer-subtitle">Historical Reliability</p>
            <div className="drawer-matrix-container">
              <Sparkline data={sparklineData} routeId={routeId} />
            </div>
          </div>
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
  );
}
