import { useState, useRef, useEffect, type ComponentChildren } from 'preact/hooks';

interface BottomSheetProps {
  children: ComponentChildren;
  detents?: number[]; // percentages, e.g. [15, 50, 90]
  defaultDetent?: number;
  isOpen: boolean;
}

export function BottomSheet({ children, detents = [15, 50, 90], defaultDetent = 15, isOpen }: BottomSheetProps) {
  const [currentDetentIndex, setCurrentDetentIndex] = useState(() => {
    const idx = detents.indexOf(defaultDetent);
    return idx !== -1 ? idx : 0;
  });
  const sheetRef = useRef<HTMLDivElement>(null);
  const startY = useRef(0);
  const currentY = useRef(0);
  const isDragging = useRef(false);
  const contentRef = useRef<HTMLDivElement>(null);

  // We map detent percentages to viewport heights
  const currentHeight = isOpen ? detents[currentDetentIndex] : 0;

  const handleTouchStart = (e: TouchEvent) => {
    // If the target is within scrollable content and we're at a larger detent,
    // let it scroll if not at the top.
    const target = e.target as HTMLElement;
    if (contentRef.current?.contains(target)) {
      if (contentRef.current.scrollTop > 0) {
        return; // Let native scroll handle it
      }
    }
    
    isDragging.current = true;
    startY.current = e.touches[0].clientY;
    currentY.current = e.touches[0].clientY;
    if (sheetRef.current) {
      sheetRef.current.style.transition = 'none';
    }
  };

  const handleTouchMove = (e: TouchEvent) => {
    if (!isDragging.current) return;
    const deltaY = e.touches[0].clientY - startY.current;
    
    // Prevent default scroll if dragging sheet
    if (Math.abs(deltaY) > 0) {
       // if we are scrolling up but at the top of content, we might drag sheet down
       const target = e.target as HTMLElement;
       if (contentRef.current?.contains(target)) {
         if (contentRef.current.scrollTop > 0) {
           return;
         }
       }
       e.preventDefault();
    }
    
    currentY.current = e.touches[0].clientY;
    if (sheetRef.current) {
      const vh = window.innerHeight;
      const currentHeightPx = (detents[currentDetentIndex] / 100) * vh;
      const newHeightPx = currentHeightPx - deltaY;
      const newHeightPercent = Math.max(0, Math.min(100, (newHeightPx / vh) * 100));
      sheetRef.current.style.height = `${newHeightPercent}vh`;
    }
  };

  const handleTouchEnd = () => {
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
      sheetRef.current.style.height = `${detents[nextIndex]}vh`;
    }
  };

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
        height: `${currentHeight}vh`,
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
