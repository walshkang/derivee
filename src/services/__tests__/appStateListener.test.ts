import { handleAppStateChange, initAppStateListener, removeAppStateListener } from '../appStateListener';
import { useExplorationStore } from '../../store/useExplorationStore';
import { AppState } from 'react-native';

describe('appStateListener Service', () => {
  let commitSpy: jest.SpyInstance;

  beforeEach(() => {
    jest.clearAllMocks();
    useExplorationStore.getState().resetExploration();
    commitSpy = jest.spyOn(useExplorationStore.getState(), 'commitActiveBuffer').mockResolvedValue(0);
  });

  afterEach(() => {
    commitSpy.mockRestore();
    removeAppStateListener();
  });

  it('should trigger commitActiveBuffer when app state changes to background or inactive', () => {
    handleAppStateChange('background');
    expect(commitSpy).toHaveBeenCalledTimes(1);

    handleAppStateChange('inactive');
    expect(commitSpy).toHaveBeenCalledTimes(2);
  });

  it('should not trigger commitActiveBuffer when app state is active', () => {
    handleAppStateChange('active');
    expect(commitSpy).not.toHaveBeenCalled();
  });

  it('should attach and remove AppState subscription properly', () => {
    const addEventListenerSpy = jest.spyOn(AppState, 'addEventListener');

    const cleanup = initAppStateListener();

    expect(addEventListenerSpy).toHaveBeenCalledWith('change', expect.any(Function));

    cleanup();
    addEventListenerSpy.mockRestore();
  });
});
