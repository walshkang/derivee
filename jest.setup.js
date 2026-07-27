// Silence the warning: Animated: `useNativeDriver` is not supported
jest.mock('react-native/Libraries/Animated/NativeAnimatedHelper');

// Manual mock for @op-engineering/op-sqlite per AGENTS.md rules
jest.mock('@op-engineering/op-sqlite', () => {
  const store = new Map();
  const executedQueries = [];

  const mockDb = {
    execute: jest.fn((query, params) => {
      executedQueries.push(query);

      if (query.includes('PRAGMA journal_mode')) {
        return { rows: { _array: [{ journal_mode: 'wal' }] } };
      }

      if (query.includes('PRAGMA synchronous')) {
        return { rows: { _array: [{ synchronous: 1 }] } };
      }

      if (query.includes('CREATE TABLE')) {
        return { rows: { _array: [] } };
      }

      if (query.includes('INSERT OR IGNORE')) {
        if (params && params.length >= 2) {
          const [h3Index, discoveredAt] = params;
          if (typeof h3Index === 'string' && !store.has(h3Index)) {
            store.set(h3Index, { h3_index: h3Index, discovered_at: Number(discoveredAt) });
          }
        }
        return { rows: { _array: [] } };
      }

      if (query.includes('SELECT h3_index FROM explored_hexes')) {
        return {
          rows: {
            _array: Array.from(store.values()).map((item) => ({ h3_index: item.h3_index })),
          },
        };
      }

      if (query.includes('SELECT COUNT(*)')) {
        return {
          rows: {
            _array: [{ count: store.size, 'COUNT(*)': store.size }],
          },
        };
      }

      if (query.includes('SELECT * FROM pois')) {
        return {
          rows: {
            _array: [
              {
                id: 'poi_1',
                name: 'Domino Park',
                description: 'A beautiful waterfront park built on the former Domino Sugar Refinery site.',
                latitude: 40.7153,
                longitude: -73.9678,
                h3_index: '8b2a100d213fff',
                discovered: 0,
                reward_type: 'Silver Coin',
              },
            ],
          },
        };
      }

      if (query.includes('DELETE FROM explored_hexes')) {
        store.clear();
        return { rows: { _array: [] } };
      }

      return { rows: { _array: [] } };
    }),

    transaction: jest.fn((fn) => {
      const tx = {
        execute: (query, params) => mockDb.execute(query, params),
      };
      fn(tx);
    }),

    close: jest.fn(() => {
      store.clear();
    }),

    // Test utilities exposed on mock
    _store: store,
    _executedQueries: executedQueries,
    _reset: () => {
      store.clear();
      executedQueries.length = 0;
    },
  };

  return {
    open: jest.fn(() => mockDb),
    DB: jest.fn(),
  };
});

// Manual mock for expo-task-manager
jest.mock('expo-task-manager', () => {
  const tasks = new Map();

  return {
    defineTask: jest.fn((taskName, taskExecutor) => {
      tasks.set(taskName, taskExecutor);
    }),
    isTaskDefined: jest.fn((taskName) => tasks.has(taskName)),
    isTaskRegisteredAsync: jest.fn(async (taskName) => tasks.has(taskName)),
    unregisterAllTasksAsync: jest.fn(async () => {
      tasks.clear();
    }),
    _definedTasks: tasks,
  };
});

// Manual mock for expo-location
jest.mock('expo-location', () => {
  let isTrackingStarted = false;

  return {
    Accuracy: {
      Lowest: 1,
      Low: 2,
      Balanced: 3,
      High: 4,
      Highest: 5,
      BestForNavigation: 6,
    },
    ActivityType: {
      Other: 1,
      AutomotiveNavigation: 2,
      Fitness: 3,
      OtherNavigation: 4,
      Airborne: 5,
    },
    requestForegroundPermissionsAsync: jest.fn(async () => ({
      status: 'granted',
      granted: true,
    })),
    requestBackgroundPermissionsAsync: jest.fn(async () => ({
      status: 'granted',
      granted: true,
    })),
    getForegroundPermissionsAsync: jest.fn(async () => ({
      status: 'granted',
      granted: true,
    })),
    getBackgroundPermissionsAsync: jest.fn(async () => ({
      status: 'granted',
      granted: true,
    })),
    startLocationUpdatesAsync: jest.fn(async (taskName, options) => {
      isTrackingStarted = true;
    }),
    stopLocationUpdatesAsync: jest.fn(async (taskName) => {
      isTrackingStarted = false;
    }),
    hasStartedLocationUpdatesAsync: jest.fn(async (taskName) => {
      return isTrackingStarted;
    }),
    _setIsTrackingStarted: (val) => {
      isTrackingStarted = val;
    },
  };
});

// Manual mock for @maplibre/maplibre-react-native per AGENTS.md rules
jest.mock('@maplibre/maplibre-react-native', () => {
  const React = require('react');
  const { View } = require('react-native');

  const MockMapView = (props: any) => React.createElement(View, { testID: 'map-placeholder', ...props }, props.children);
  const MockCamera = React.forwardRef((props: any, ref: any) => null);
  const MockUserLocation = () => null;
  const MockShapeSource = (props: any) => React.createElement(View, props, props.children);
  const MockFillLayer = () => null;
  const MockCircleLayer = () => null;
  const MockRasterDemSource = (props: any) => React.createElement(View, props, props.children);
  const MockTerrain = () => null;
  const MockRasterSource = (props: any) => React.createElement(View, props, props.children);
  const MockRasterLayer = () => null;

  return {
    __esModule: true,
    default: {
      MapView: MockMapView,
      Camera: MockCamera,
      UserLocation: MockUserLocation,
      ShapeSource: MockShapeSource,
      FillLayer: MockFillLayer,
      CircleLayer: MockCircleLayer,
      RasterDemSource: MockRasterDemSource,
      Terrain: MockTerrain,
      RasterSource: MockRasterSource,
      RasterLayer: MockRasterLayer,
      setAccessToken: jest.fn(),
      setWellKnownTileServer: jest.fn(),
    },
    MapView: MockMapView,
    Camera: MockCamera,
    UserLocation: MockUserLocation,
    ShapeSource: MockShapeSource,
    FillLayer: MockFillLayer,
    CircleLayer: MockCircleLayer,
    RasterDemSource: MockRasterDemSource,
    Terrain: MockTerrain,
    RasterSource: MockRasterSource,
    RasterLayer: MockRasterLayer,
    setAccessToken: jest.fn(),
    setWellKnownTileServer: jest.fn(),
  };
});

// Manual mock for react-native-reanimated
jest.mock('react-native-reanimated', () => {
  const React = require('react');
  const { View } = require('react-native');
  return {
    __esModule: true,
    default: {
      View: (props: any) => React.createElement(View, props, props.children),
      Text: (props: any) => React.createElement(View, props, props.children),
    },
    useSharedValue: (val: any) => ({ value: val }),
    useDerivedValue: (fn: any) => ({ value: fn() }),
    useAnimatedStyle: (fn: any) => fn() || {},
    withTiming: (toValue: any) => toValue,
    withSpring: (toValue: any) => toValue,
    withSequence: (...args: any[]) => args[args.length - 1],
    withDelay: (delay: any, animation: any) => animation,
    runOnJS: (fn: any) => fn,
    Easing: {
      inOut: () => {},
      ease: {},
    },
  };
});

// Configure jest-image-snapshot
const { toMatchImageSnapshot } = require('jest-image-snapshot');
expect.extend({ toMatchImageSnapshot });

jest.mock('@shopify/react-native-skia', () => ({
  Canvas: 'Canvas',
  Rect: 'Rect',
  Circle: 'Circle',
  Mask: 'Mask',
  Group: 'Group',
  RadialGradient: 'RadialGradient',
  vec: jest.fn((x, y) => ({ x, y })),
}));
