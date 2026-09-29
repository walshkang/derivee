export type UIState = 'loading' | 'ready' | 'error';

export function getTransitLayerDisplayState(state: UIState, rawError?: string): { badge: string; text: string } {
  if (state === 'loading') {
    return { badge: 'loading', text: 'Loading Transit Layer' };
  }
  if (state === 'error') {
    // Ban internal IDs, paths, or technical errors from UI copy
    // A pure display model function
    return { badge: 'error', text: 'Transit Data Unavailable' };
  }
  return { badge: 'ready', text: 'Transit Ready' };
}
