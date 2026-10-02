# DeriveeWeb Invariants

This document codifies interaction and architectural invariants for Dérivée Web.
All UI components, styles, and gesture controllers must comply with these rules.

---

## 1. Scroll-Container Invariant

### Definition
Every scrollable element within the application must explicitly declare its scroll container bounds, overflow behaviors, and interaction isolation boundaries relative to gesture-manipulated ancestors.

### Rules

1. **Explicit Container Declaration & Height Bounds**
   - Every scrollable region must declare `overflow-y: auto` (or `scroll`).
   - Every scrollable region must have an unbroken chain of bounded height constraints up to a viewport or layout root (`height`, `max-height`, or flex item with `min-height: 0` and parent flex constraint).
   - Touch scrolling must be enabled via `-webkit-overflow-scrolling: touch`.
   - Nested scrollable containers should declare `overscroll-behavior: contain` to prevent scroll chaining to outer containers.

2. **Nested Gesture Priority & Seam Isolation**
   - When scrollable containers are placed inside a gesture-driven parent (such as a draggable, multi-detent `BottomSheet`), the gesture system must grant interaction priority to the innermost scrollable container under the touch point.
   - A parent gesture controller must **never** inspect only its immediate container (e.g. `.bottom-sheet-content.scrollTop`) when deciding whether to yield to native scroll. It must inspect the actual touch target's scroll context (the closest scrollable ancestor between the target and the sheet root).
   - **Gesture Hand-off Invariant**:
     - **Swipe Up / Content Scrolling Down (`deltaY < 0`)**: Inner scrollable retains exclusive priority until reaching maximum scroll (`scrollTop >= scrollHeight - clientHeight`). The parent sheet must not call `preventDefault()`, must not drag, and must not change detents.
     - **Swipe Down / Content Scrolling Up (`deltaY > 0`)**:
       - While inner container `scrollTop > 0`: Inner scrollable retains exclusive priority (scrolls up towards top). Parent sheet must not call `preventDefault()`.
       - When inner container `scrollTop === 0`: Parent sheet may capture gesture to drag/collapse detent.
     - Touches originating on non-scrollable sheet elements (drag handle, headers) are captured by the sheet controller immediately.

### Verification Procedure
1. **Computed Style Check**: Verify `overflow-y`, bounded heights (`max-height` or `flex` with `min-height: 0`), and absence of accidental `touch-action: none` on scrollable content.
2. **Behavioral Renderer Check**: In an automated headless browser harness (Playwright), dispatch synthetic touch gestures on the nested scrollable content and assert:
   - `preventDefault() === false` during touchmove while inner container is scrollable.
   - Inner container `scrollTop` increases on swipe up.
   - Parent sheet height/detent remains strictly unchanged.
