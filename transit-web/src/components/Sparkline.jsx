import React from 'react';
import { getRouteColor } from '../services/transitConfig';
import './Sparkline.css';

export default function Sparkline({ data, routeId }) {
  if (!data || data.length === 0) {
    return <div className="sparkline-empty">No historical data available</div>;
  }

  // We are plotting 168 hours of the week
  const svgWidth = 300;
  const svgHeight = 60;
  
  // min and max of data to scale the Y axis
  const minVal = Math.min(...data);
  const maxVal = Math.max(...data);
  const range = maxVal - minVal || 1; // avoid division by zero
  
  const stepX = svgWidth / Math.max(data.length - 1, 1);
  
  // generate points
  const points = data.map((val, idx) => {
    const x = idx * stepX;
    // invert Y because SVG 0,0 is top left
    // We add some padding (5) so the stroke doesn't get clipped
    const padding = 5;
    const availableHeight = svgHeight - padding * 2;
    const normalizedVal = (val - minVal) / range;
    const y = svgHeight - padding - (normalizedVal * availableHeight);
    return { x, y };
  });

  const pathD = points.map((p, i) => (i === 0 ? `M ${p.x},${p.y}` : `L ${p.x},${p.y}`)).join(' ');
  const areaD = `${pathD} L ${points[points.length - 1].x},${svgHeight} L ${points[0].x},${svgHeight} Z`;

  const color = '#FFB300';

  return (
    <div className="sparkline-container">
      <svg viewBox={`0 0 ${svgWidth} ${svgHeight}`} preserveAspectRatio="none" className="sparkline-svg">
        <path d={areaD} className="sparkline-area" fill={color} fillOpacity="0.15" />
        <path d={pathD} className="sparkline-stroke" stroke={color} strokeWidth="2" fill="none" vectorEffect="non-scaling-stroke" />
      </svg>
      <div className="sparkline-labels">
        <span>Mon</span>
        <span>Wed</span>
        <span>Fri</span>
        <span>Sun</span>
      </div>
    </div>
  );
}
