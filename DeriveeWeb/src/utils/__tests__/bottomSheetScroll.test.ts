import { describe, it } from 'node:test';
import assert from 'node:assert';
import { findScrollableAncestor, shouldYieldToScroll } from '../bottomSheetScroll.ts';

interface MockElement {
  nodeType?: number;
  parentElement: MockElement | null;
  scrollHeight: number;
  clientHeight: number;
  scrollTop: number;
  style: {
    overflowY?: string;
  };
  contains?: (el: MockElement) => boolean;
}

function createMockElement(opts: Partial<MockElement> = {}): MockElement {
  const el: MockElement = {
    nodeType: opts.nodeType ?? 1,
    parentElement: opts.parentElement ?? null,
    scrollHeight: opts.scrollHeight ?? 100,
    clientHeight: opts.clientHeight ?? 100,
    scrollTop: opts.scrollTop ?? 0,
    style: opts.style ?? {},
  };
  el.contains = (target: MockElement) => {
    let cur: MockElement | null = target;
    while (cur) {
      if (cur === el) return true;
      cur = cur.parentElement;
    }
    return false;
  };
  return el;
}

describe('BottomSheet nested scroll detection (findScrollableAncestor)', () => {
  it('identifies an inner scrollable ancestor with overflow-y: auto and scrollHeight > clientHeight', () => {
    const boundary = createMockElement({ clientHeight: 500, scrollHeight: 500 });
    const card = createMockElement({
      parentElement: boundary,
      clientHeight: 200,
      scrollHeight: 400,
      style: { overflowY: 'auto' },
    });
    const button = createMockElement({
      parentElement: card,
      clientHeight: 40,
      scrollHeight: 40,
    });

    const found = findScrollableAncestor(button as unknown as HTMLElement, boundary as unknown as HTMLElement);
    assert.strictEqual(found, card);
  });

  it('identifies target when target itself is the scrollable container', () => {
    const boundary = createMockElement({ clientHeight: 500, scrollHeight: 500 });
    const card = createMockElement({
      parentElement: boundary,
      clientHeight: 200,
      scrollHeight: 400,
      style: { overflowY: 'scroll' },
    });

    const found = findScrollableAncestor(card as unknown as HTMLElement, boundary as unknown as HTMLElement);
    assert.strictEqual(found, card);
  });

  it('identifies the innermost scrollable ancestor when scrollables are nested', () => {
    const boundary = createMockElement({ clientHeight: 800, scrollHeight: 800 });
    const outerScroller = createMockElement({
      parentElement: boundary,
      clientHeight: 400,
      scrollHeight: 800,
      style: { overflowY: 'auto' },
    });
    const innerCard = createMockElement({
      parentElement: outerScroller,
      clientHeight: 200,
      scrollHeight: 500,
      style: { overflowY: 'auto' },
    });
    const leaf = createMockElement({
      parentElement: innerCard,
      clientHeight: 30,
      scrollHeight: 30,
    });

    const found = findScrollableAncestor(leaf as unknown as HTMLElement, boundary as unknown as HTMLElement);
    assert.strictEqual(found, innerCard);
  });

  it('navigates from non-element node (text node) up to parent element', () => {
    const boundary = createMockElement({ clientHeight: 500, scrollHeight: 500 });
    const card = createMockElement({
      parentElement: boundary,
      clientHeight: 200,
      scrollHeight: 400,
      style: { overflowY: 'auto' },
    });
    const textNode: MockElement = {
      nodeType: 3,
      parentElement: card,
      clientHeight: 0,
      scrollHeight: 0,
      scrollTop: 0,
      style: {},
    };

    const found = findScrollableAncestor(textNode as unknown as HTMLElement, boundary as unknown as HTMLElement);
    assert.strictEqual(found, card);
  });

  it('negative case: ignores element with overflow-y: visible even if scrollHeight > clientHeight', () => {
    const boundary = createMockElement({ clientHeight: 500, scrollHeight: 500 });
    const card = createMockElement({
      parentElement: boundary,
      clientHeight: 200,
      scrollHeight: 400,
      style: { overflowY: 'visible' },
    });
    const leaf = createMockElement({
      parentElement: card,
      clientHeight: 40,
      scrollHeight: 40,
    });

    const found = findScrollableAncestor(leaf as unknown as HTMLElement, boundary as unknown as HTMLElement);
    assert.strictEqual(found, null);
  });

  it('negative case: ignores element with overflow-y: hidden', () => {
    const boundary = createMockElement({ clientHeight: 500, scrollHeight: 500 });
    const card = createMockElement({
      parentElement: boundary,
      clientHeight: 200,
      scrollHeight: 400,
      style: { overflowY: 'hidden' },
    });

    const found = findScrollableAncestor(card as unknown as HTMLElement, boundary as unknown as HTMLElement);
    assert.strictEqual(found, null);
  });

  it('negative case: ignores element with overflow-y: auto when content fits (scrollHeight <= clientHeight)', () => {
    const boundary = createMockElement({ clientHeight: 500, scrollHeight: 500 });
    const card = createMockElement({
      parentElement: boundary,
      clientHeight: 300,
      scrollHeight: 300,
      style: { overflowY: 'auto' },
    });

    const found = findScrollableAncestor(card as unknown as HTMLElement, boundary as unknown as HTMLElement);
    assert.strictEqual(found, null);
  });

  it('negative case: returns null when target is outside boundary', () => {
    const boundary = createMockElement({ clientHeight: 500, scrollHeight: 500 });
    const outsideParent = createMockElement();
    const outsideCard = createMockElement({
      parentElement: outsideParent,
      clientHeight: 200,
      scrollHeight: 400,
      style: { overflowY: 'auto' },
    });

    const found = findScrollableAncestor(outsideCard as unknown as HTMLElement, boundary as unknown as HTMLElement);
    assert.strictEqual(found, null);
  });

  it('negative case: returns null when target or boundary is null', () => {
    const boundary = createMockElement();
    assert.strictEqual(findScrollableAncestor(null, boundary as unknown as HTMLElement), null);
    assert.strictEqual(findScrollableAncestor(null, null), null);
  });
});

describe('BottomSheet scroll vs drag decision (shouldYieldToScroll)', () => {
  it('swipe up (deltaY < 0): yields when inner container can scroll down (scrollTop < maxScroll)', () => {
    const scrollable = createMockElement({
      clientHeight: 200,
      scrollHeight: 600,
      scrollTop: 0,
    });
    // deltaY < 0 means finger moving up, content scrolls down
    const shouldYield = shouldYieldToScroll(scrollable as unknown as HTMLElement, -20);
    assert.strictEqual(shouldYield, true);
  });

  it('swipe up (deltaY < 0): negative case - does NOT yield when inner container is already at bottom edge', () => {
    const scrollable = createMockElement({
      clientHeight: 200,
      scrollHeight: 600,
      scrollTop: 400, // maxScroll = 600 - 200 = 400
    });
    const shouldYield = shouldYieldToScroll(scrollable as unknown as HTMLElement, -20);
    assert.strictEqual(shouldYield, false);
  });

  it('swipe down (deltaY > 0): yields when inner container is scrolled down (scrollTop > 0)', () => {
    const scrollable = createMockElement({
      clientHeight: 200,
      scrollHeight: 600,
      scrollTop: 50,
    });
    // deltaY > 0 means finger moving down, content scrolls up towards 0
    const shouldYield = shouldYieldToScroll(scrollable as unknown as HTMLElement, 20);
    assert.strictEqual(shouldYield, true);
  });

  it('swipe down (deltaY > 0): negative case - does NOT yield when inner container is at top edge (scrollTop == 0)', () => {
    const scrollable = createMockElement({
      clientHeight: 200,
      scrollHeight: 600,
      scrollTop: 0,
    });
    // Inner at top edge: sheet should engage drag instead of yielding
    const shouldYield = shouldYieldToScroll(scrollable as unknown as HTMLElement, 20);
    assert.strictEqual(shouldYield, false);
  });

  it('negative case: does not yield when scrollable is null', () => {
    assert.strictEqual(shouldYieldToScroll(null, -20), false);
    assert.strictEqual(shouldYieldToScroll(null, 20), false);
  });

  it('negative case: does not yield when deltaY is 0', () => {
    const scrollable = createMockElement({
      clientHeight: 200,
      scrollHeight: 600,
      scrollTop: 50,
    });
    assert.strictEqual(shouldYieldToScroll(scrollable as unknown as HTMLElement, 0), false);
  });
});
