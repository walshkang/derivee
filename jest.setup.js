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
