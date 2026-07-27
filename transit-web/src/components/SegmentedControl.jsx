import React from 'react';
import './SegmentedControl.css';

export default function SegmentedControl({ options, selected, onChange }) {
  return (
    <div className="segmented-control glass">
      {options.map((option) => (
        <button
          key={option.value}
          className={`segment-btn ${selected === option.value ? 'selected' : ''}`}
          onClick={() => onChange(option.value)}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}
