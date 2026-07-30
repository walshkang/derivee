import { useState, useEffect } from 'react';
import SegmentedControl from './components/SegmentedControl';
import TransitBottomSheet from './components/TransitBottomSheet';
import TransitMap from './components/TransitMap';
import { historianService } from './services/historianService';
import { transitService } from './services/transitService';
import './App.css';

function App() {
  const [activeMode, setActiveMode] = useState('subway');
  const [isSheetOpen, setIsSheetOpen] = useState(false);
  const [selectedNode, setSelectedNode] = useState(null);
  const [sparklineData, setSparklineData] = useState([]);
  const [liveArrivals, setLiveArrivals] = useState([]);

  useEffect(() => {
    // Pre-initialize historian service db
    historianService.init();
  }, []);

  const handleNodeTap = async (node) => {
    setSelectedNode(node);
    
    // Fetch sparkline data for the clicked route
    const data = await historianService.getSparklineData(node.route || node.routeId, node.stopId || 'test_stop');
    setSparklineData(data);
    
    // Fetch live arrivals
    try {
      if (activeMode === 'bus') {
        const live = await transitService.fetchBusStopLive(node.stopId);
        setLiveArrivals(live.arrivals || []);
      } else {
        const routeId = node.route || node.routeId;
        let feedKey = null;
        if (routeId) {
          const r = routeId.toUpperCase();
          if (['A','C','E'].includes(r)) feedKey = 'ACE';
          else if (['B','D','F','M'].includes(r)) feedKey = 'BDFM';
          else if (['G'].includes(r)) feedKey = 'G';
          else if (['J','Z'].includes(r)) feedKey = 'JZ';
          else if (['N','Q','R','W'].includes(r)) feedKey = 'NQRW';
          else if (['L'].includes(r)) feedKey = 'L';
          else if (['1','2','3','4','5','6','7'].includes(r)) feedKey = 'NUMBERED';
          else if (['SIR'].includes(r)) feedKey = 'SIR';
        }
        
        if (feedKey) {
          const live = await transitService.fetchSubwayFeed(feedKey);
          // Filter arrivals by stopId
          const stationArrivals = live.arrivals.filter(a => a.stopId === node.stopId || a.stopId.startsWith(node.stopId));
          // Sort by arrival time
          stationArrivals.sort((a, b) => a.arrivalTime - b.arrivalTime);
          setLiveArrivals(stationArrivals.slice(0, 5)); // show next 5
        } else {
          setLiveArrivals([]);
        }
      }
    } catch (e) {
      console.error('Failed to fetch live arrivals', e);
      setLiveArrivals([]);
    }
    
    setIsSheetOpen(true);
  };

  return (
    <div className="app-container">
      {/* Zero-Tap Map Header / Mode Switcher */}
      <SegmentedControl 
        options={[
          { label: 'Subways', value: 'subway' },
          { label: 'Buses', value: 'bus' }
        ]} 
        selected={activeMode} 
        onChange={setActiveMode} 
      />

      {/* Map Engine */}
      <main className="map-container">
        <TransitMap 
          activeMode={activeMode} 
          onNodeTap={handleNodeTap} 
        />
      </main>

      {/* Bottom Sheet */}
      <TransitBottomSheet 
        open={isSheetOpen} 
        onOpenChange={setIsSheetOpen}
        stationName={selectedNode ? `Route ${selectedNode.route || selectedNode.routeId}` : "Transit Node"}
        sparklineData={sparklineData}
        liveArrivals={liveArrivals}
        routeId={selectedNode ? (selectedNode.route || selectedNode.routeId) : null}
      />
    </div>
  );
}

export default App;
