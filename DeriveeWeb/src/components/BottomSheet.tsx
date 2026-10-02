import { useState, useRef, useEffect } from 'preact/hooks';
import type { ComponentChildren } from 'preact';

interface BottomSheetProps {
  children: ComponentChildren;
  detents?: number[]; // percentages, e.g. [15, 50, 90]
  defaultDetent?: number;
  activeDetent?: number;
  onDetentChange?: (detent: number) => void;
  isOpen: boolean;
}

import { findScrollableAncestor, shouldYieldToScroll } from '../utils/bottomSheetScroll';

export function BottomSheet({
  children,
  detents = [15, 50, 90],
  defaultDetent = 15,
  activeDetent,
  onDetentChange,
  isOpen,
}: BottomSheetProps) {
  const [currentDetentIndex, setCurrentDetentIndex] = useState(() => {
    const initial = activeDetent !== undefined ? activeDetent : defaultDetent;
    const idx = detents.indexOf(initial);
    return idx !== -1 ? idx : 0;
  });

  const sheetRef = useRef<HTMLDivElement>(null);
  const startY = useRef(0);
  const currentY = useRef(0);
  const isDragging = useRef(false);
  const isInnerScroll = useRef(false);
  const contentRef = useRef<HTMLDivElement>(null);

  // We map detent percentages to viewport heights
  const currentHeight = isOpen ? detents[currentDetentIndex] : 0;

  const handleTouchStart = (e: TouchEvent) => {
    if (!e.touches || e.touches.length === 0) return;
    const target = e.target as HTMLElement | null;
    startY.current = e.touches[0].clientY;
    currentY.current = e.touches[0].clientY;
    isInnerScroll.current = false;

    const isHandle = Boolean(target && (target as Element).closest?.('.bottom-sheet-handle-container'));
    if (isHandle) {
      isDragging.current = true;
      if (sheetRef.current) {
        sheetRef.current.style.transition = 'none';
      }
    } else {
      isDragging.current = false;
    }
  };

  const handleTouchMove = (e: TouchEvent) => {
    if (!e.touches || e.touches.length === 0) return;
    const deltaY = e.touches[0].clientY - startY.current;

    if (isInnerScroll.current) {
      return; // Committed to native scroll for this gesture
    }

    if (!isDragging.current) {
      const target = e.target as HTMLElement | null;
      const scrollable = findScrollableAncestor(target, contentRef.current);
      if (shouldYieldToScroll(scrollable, deltaY)) {
        isInnerScroll.current = true;
        return; // Yield to native scroll — do not set isDragging, do not preventDefault
      }

      // If we don't yield (inner container at scroll edge or not scrollable), engage sheet drag
      if (Math.abs(deltaY) > 0) {
        isDragging.current = true;
        if (sheetRef.current) {
          sheetRef.current.style.transition = 'none';
        }
      }
    }

    if (!isDragging.current) return;

    if (Math.abs(deltaY) > 0) {
      e.preventDefault();
    }
    
    currentY.current = e.touches[0].clientY;
    if (sheetRef.current) {
      const vh = window.innerHeight;
      const currentHeightPx = (detents[currentDetentIndex] / 100) * vh;
      const newHeightPx = currentHeightPx - deltaY;
      const newHeightPercent = Math.max(0, Math.min(100, (newHeightPx / vh) * 100));
      sheetRef.current.style.height = `${newHeightPercent}dvh`;
    }
  };

  const handleTouchEnd = () => {
    isInnerScroll.current = false;
    if (!isDragging.current) return;
    isDragging.current = false;
    if (sheetRef.current) {
      sheetRef.current.style.transition = 'height 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275)';
      
      const deltaY = currentY.current - startY.current;
      const threshold = window.innerHeight * 0.05; // 5% of screen height to trigger state change
      
      let nextIndex = currentDetentIndex;
      if (deltaY < -threshold && currentDetentIndex < detents.length - 1) {
        // Dragged up
        nextIndex = currentDetentIndex + 1;
      } else if (deltaY > threshold && currentDetentIndex > 0) {
        // Dragged down
        nextIndex = currentDetentIndex - 1;
      }
      
      setCurrentDetentIndex(nextIndex);
      onDetentChange?.(detents[nextIndex]);
      sheetRef.current.style.height = `${detents[nextIndex]}dvh`;
    }
  };

  useEffect(() => {
    if (activeDetent !== undefined) {
      const idx = detents.indexOf(activeDetent);
      if (idx !== -1 && idx !== currentDetentIndex) {
        setCurrentDetentIndex(idx);
        if (sheetRef.current) {
          sheetRef.current.style.transition = 'height 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275)';
          sheetRef.current.style.height = `${detents[idx]}dvh`;
        }
      }
    }
  }, [activeDetent, detents]);

  useEffect(() => {
    const sheet = sheetRef.current;
    if (sheet) {
      sheet.addEventListener('touchstart', handleTouchStart, { passive: false });
      sheet.addEventListener('touchmove', handleTouchMove, { passive: false });
      sheet.addEventListener('touchend', handleTouchEnd);
      return () => {
        sheet.removeEventListener('touchstart', handleTouchStart);
        sheet.removeEventListener('touchmove', handleTouchMove);
        sheet.removeEventListener('touchend', handleTouchEnd);
      };
    }
  }, [currentDetentIndex]);


  return (
    <div 
      ref={sheetRef}
      class="bottom-sheet"
      style={{
        height: `${currentHeight}dvh`,
        transition: 'height 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275)',
        visibility: currentHeight === 0 ? 'hidden' : 'visible'
      }}
    >
      <div class="bottom-sheet-handle-container">
        <div class="bottom-sheet-handle" />
      </div>
      <div class="bottom-sheet-content" ref={contentRef}>
        {children}
      </div>
    </div>
  );
}
