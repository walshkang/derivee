import { useState, useEffect } from 'react';
import SegmentedControl from './components/SegmentedControl';
import TransitBottomSheet from './components/TransitBottomSheet';
import TransitMap from './components/TransitMap';
import { historianService } from './services/historianService';
import './App.css';

function App() {
  const [activeMode, setActiveMode] = useState('subway');
  const [isSheetOpen, setIsSheetOpen] = useState(false);
  const [selectedNode, setSelectedNode] = useState(null);
  const [headwayData, setHeadwayData] = useState([]);

  useEffect(() => {
    // Pre-initialize historian service db
    historianService.init();
  }, []);

  const handleNodeTap = async (node) => {
    setSelectedNode(node);
    
    // Fetch headway data for the clicked route
    const data = await historianService.getHeadwayData(node.route || node.routeId, node.stopId || 'test_stop');
    setHeadwayData(data);
    
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
        headwayData={headwayData}
      />
    </div>
  );
}

export default App;
