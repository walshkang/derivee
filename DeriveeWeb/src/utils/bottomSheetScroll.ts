/**
 * Nested scroll container detection and touch gesture yielding for BottomSheet.
 */

/**
 * Detect the scrollable ancestor under the touch point.
 * Walks from target up to boundary; a scrollable has overflow-y: auto|scroll
 * and scrollHeight > clientHeight.
 */
export function findScrollableAncestor(
  target: EventTarget | null,
  boundary: HTMLElement | null
): HTMLElement | null {
  if (boundary && typeof boundary.contains === 'function' && target && !boundary.contains(target as Node)) {
    return null;
  }

  let curr: HTMLElement | null = null;
  if (target) {
    if (typeof (target as Node).nodeType === 'number' && (target as Node).nodeType !== 1) {
      // Non-element node (e.g. text node) -> start from parent element
      curr = (target as Node).parentElement as HTMLElement | null;
    } else {
      curr = target as HTMLElement;
    }
  }

  while (curr) {
    const style = typeof window !== 'undefined' && window.getComputedStyle
      ? window.getComputedStyle(curr)
      : (curr as unknown as { style?: CSSStyleDeclaration }).style;

    const overflowY = style?.overflowY;
    if (
      (overflowY === 'auto' || overflowY === 'scroll') &&
      curr.scrollHeight > curr.clientHeight
    ) {
      return curr;
    }

    if (curr === boundary) {
      break;
    }
    curr = curr.parentElement;
  }

  return null;
}

/**
 * Decides whether a touchmove gesture should yield to native scroll of an inner container.
 * - Swipe up (deltaY < 0): if inner scrollable can still move down (scrollTop < scrollHeight - clientHeight),
 *   yield to native scroll.
 * - Swipe down (deltaY > 0): if inner scrollTop > 0, yield to native scroll.
 *   Only when the inner container is at its scroll edge (top on downward drag) does sheet drag engage.
 */
export function shouldYieldToScroll(
  scrollable: HTMLElement | null,
  deltaY: number
): boolean {
  if (!scrollable) return false;

  // Swipe up (deltaY < 0): inner scrollable moves down
  if (deltaY < 0) {
    const maxScroll = scrollable.scrollHeight - scrollable.clientHeight;
    return scrollable.scrollTop < maxScroll;
  }

  // Swipe down (deltaY > 0): inner scrollable moves up
  if (deltaY > 0) {
    return scrollable.scrollTop > 0;
  }

  return false;
}
