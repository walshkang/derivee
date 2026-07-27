import React from 'react';
import { render, fireEvent, act } from '@testing-library/react-native';
import SplashScreen from '../index';
import MapScreen from '../(tabs)/map';
import ArchiveScreen from '../(tabs)/archive';
import { useExplorationStore } from '@/store/useExplorationStore';

// Mock expo-router
const mockReplace = jest.fn();
const mockPush = jest.fn();

jest.mock('expo-router', () => ({
  useRouter: () => ({
    replace: mockReplace,
    push: mockPush,
  }),
  Stack: ({ children }: { children?: React.ReactNode }) => <>{children}</>,
  Tabs: Object.assign(
    ({ children }: { children?: React.ReactNode }) => <>{children}</>,
    {
      Screen: () => null,
    }
  ),
}));

describe('Wave 1 Navigation Shell & Screens (W1-NAV)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    useExplorationStore.getState().resetExploration();
  });

  describe('SplashScreen ("The Awakening")', () => {
    it('renders app title, subtitle, and awakening button', () => {
      const { getByText } = render(<SplashScreen />);

      expect(getByText('FOG OF WBURG')).toBeTruthy();
      expect(getByText("The Cartographer's Awakening")).toBeTruthy();
      expect(getByText('AWAKEN MAP')).toBeTruthy();
    });

    it('navigates to tabs map when AWAKEN MAP button is pressed', () => {
      const { getByText } = render(<SplashScreen />);
      const awakenButton = getByText('AWAKEN MAP');

      fireEvent.press(awakenButton);
      expect(mockReplace).toHaveBeenCalledWith('/(tabs)/map');
    });
  });

  describe('MapScreen ("The Cartographer\'s Desk")', () => {
    it('renders the MapLibre viewport and ambient status badge', () => {
      const { getByTestId, getByText } = render(<MapScreen />);

      expect(getByTestId('map-placeholder')).toBeTruthy();
      expect(getByText('AMBIENT STANDBY')).toBeTruthy();
    });

    it('toggles expedition state when action button is pressed', async () => {
      const { getByLabelText, getByText } = render(<MapScreen />);
      expect(useExplorationStore.getState().isExploring).toBe(false);

      const startButton = getByLabelText('Start Expedition');
      await act(async () => {
        fireEvent.press(startButton);
      });

      expect(useExplorationStore.getState().isExploring).toBe(true);
      expect(getByText('EXPEDITION ACTIVE')).toBeTruthy();
    });
  });

  describe('ArchiveScreen ("The Archive")', () => {
    it('renders overall exploration metrics and reset functionality', () => {
      useExplorationStore.getState().addUnlockedHexes(['8b2a100d213fff']);

      const { getByText } = render(<ArchiveScreen />);

      expect(getByText('THE ARCHIVE')).toBeTruthy();
      expect(getByText('Total Hexes Unlocked')).toBeTruthy();

      const resetButton = getByText('RESET EXPLORATION DATA');
      fireEvent.press(resetButton);

      expect(useExplorationStore.getState().unlockedHexes).toHaveLength(0);
      expect(useExplorationStore.getState().isExploring).toBe(false);
    });
  });
});
