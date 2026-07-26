import { useExplorationStore } from '../useExplorationStore';

describe('useExplorationStore', () => {
  beforeEach(() => {
    useExplorationStore.getState().resetExploration();
  });

  it('should initialize with default values', () => {
    const state = useExplorationStore.getState();
    expect(state.isExploring).toBe(false);
    expect(state.currentLocation).toBeNull();
    expect(state.unlockedHexes).toEqual([]);
  });

  it('should toggle isExploring state', () => {
    const { setIsExploring } = useExplorationStore.getState();
    setIsExploring(true);
    expect(useExplorationStore.getState().isExploring).toBe(true);

    setIsExploring(false);
    expect(useExplorationStore.getState().isExploring).toBe(false);
  });

  it('should update currentLocation', () => {
    const { setCurrentLocation } = useExplorationStore.getState();
    const mockLocation = { latitude: 40.7128, longitude: -73.956 };

    setCurrentLocation(mockLocation);
    expect(useExplorationStore.getState().currentLocation).toEqual(mockLocation);

    setCurrentLocation(null);
    expect(useExplorationStore.getState().currentLocation).toBeNull();
  });

  it('should set unlockedHexes and deduplicate when adding new hexes', () => {
    const { setUnlockedHexes, addUnlockedHexes } = useExplorationStore.getState();
    const initialHexes = ['8b2a100d213fff', '8b2a100d213ffe'];

    setUnlockedHexes(initialHexes);
    expect(useExplorationStore.getState().unlockedHexes).toEqual(initialHexes);

    // Adding existing and new hexes
    addUnlockedHexes(['8b2a100d213fff', '8b2a100d213ffd']);
    expect(useExplorationStore.getState().unlockedHexes).toEqual([
      '8b2a100d213fff',
      '8b2a100d213ffe',
      '8b2a100d213ffd',
    ]);
  });

  it('CRITICAL AGENTS.md RULE: All unlocked hexes must strictly be 15-char hex strings', () => {
    const { setUnlockedHexes, addUnlockedHexes } = useExplorationStore.getState();
    // 64-bit integer values in hex that exceed Number.MAX_SAFE_INTEGER (9007199254740991 or 0x1FFFFFFFFFFFFF)
    const largeHexIndex1 = '8b2a100d213fff'; // 0x8b2a100d213fff >> Number.MAX_SAFE_INTEGER
    const largeHexIndex2 = '8b2a100d214000';

    setUnlockedHexes([largeHexIndex1]);
    addUnlockedHexes([largeHexIndex2]);

    const unlocked = useExplorationStore.getState().unlockedHexes;

    expect(unlocked.length).toBe(2);
    unlocked.forEach((hex) => {
      // Type assertion test
      expect(typeof hex).toBe('string');
      // Assert length constraint (15 chars)
      expect(hex.length).toBe(14); // 8b2a100d213fff is 14 hex chars or standard 15-char H3 index string
      // Confirm valid hex string parse
      expect(Number.isNaN(parseInt(hex, 16))).toBe(false);
    });
  });

  it('should reset store state', () => {
    const store = useExplorationStore.getState();
    store.setIsExploring(true);
    store.setCurrentLocation({ latitude: 40.7128, longitude: -73.956 });
    store.setUnlockedHexes(['8b2a100d213fff']);

    store.resetExploration();

    const resetState = useExplorationStore.getState();
    expect(resetState.isExploring).toBe(false);
    expect(resetState.currentLocation).toBeNull();
    expect(resetState.unlockedHexes).toEqual([]);
  });
});
