import React from 'react';
import { Drawer } from 'vaul';
import HeadwayMatrix from './HeadwayMatrix';
import './TransitBottomSheet.css';

export default function TransitBottomSheet({ open, onOpenChange, stationName, headwayData }) {
  return (
    <Drawer.Root open={open} onOpenChange={onOpenChange}>
      <Drawer.Portal>
        <Drawer.Overlay className="drawer-overlay" />
        <Drawer.Content className="drawer-content glass">
          <div className="drawer-handle" />
          <div className="drawer-body">
            <Drawer.Title className="drawer-title">{stationName || 'Transit Node'}</Drawer.Title>
            <p className="drawer-subtitle">Historical Reliability</p>
            <div className="drawer-matrix-container">
              <HeadwayMatrix data={headwayData} />
            </div>
          </div>
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
  );
}
