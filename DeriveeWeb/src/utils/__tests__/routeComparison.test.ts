import { describe, it } from 'node:test';
import assert from 'node:assert';
import type {
  RoutingSegment,
  RoutingWorkerIncomingMessage,
  RoutingWorkerOutgoingMessage,
} from '../../types/routing.ts';
import {
  areItinerariesIdentical,
  countTransfers,
  formatTransferCount,
  formatDurationHuman,
  formatClockTime,
  formatArrivalTime,
  createRankedItinerary,
  buildRankedItineraries,
  executeDualProfileRouting,
  getRouteComparisonUIState,
  type RoutingWorkerLike,
} from '../routeComparison.ts';
import {
  ROUTING_FLAG_NONE,
  ROUTING_FLAG_AVOID_TRANSFERS,
  createRoutingWorkerHandler,
} from '../../workers/routingEngine.ts';
import { RoutingQueryWatchdog } from '../tabSuspension.ts';

describe('Screen 4B Route Comparison & Profile Ranking Tests', () => {
  // Sample test fixtures
  const directLegA: RoutingSegment = {
    board_stop_id: 101,
    exit_stop_id: 303,
    trip_id: 501,
    departure_time: 28800, // 08:00
    arrival_time: 30240, // 08:24 (24 min)
    route_id: 1,
    transfer_distance_m: 0,
    is_transfer: false,
  };

  const transferLegA1: RoutingSegment = {
    board_stop_id: 101,
    exit_stop_id: 202,
    trip_id: 601,
    departure_time: 28800,
    arrival_time: 29400, // 10 min
    route_id: 2,
    transfer_distance_m: 0,
    is_transfer: false,
  };

  const walkTransfer: RoutingSegment = {
    board_stop_id: 202,
    exit_stop_id: 202,
    trip_id: 0xFFFFFFFF,
    departure_time: 29400,
    arrival_time: 29520, // 2 min transfer
    route_id: 0xFFFF,
    transfer_distance_m: 80,
    is_transfer: true,
  };

  const transferLegA2: RoutingSegment = {
    board_stop_id: 202,
    exit_stop_id: 303,
    trip_id: 701,
    departure_time: 29580,
    arrival_time: 30120, // 08:22 (22 min total)
    route_id: 3,
    transfer_distance_m: 0,
    is_transfer: false,
  };

  describe('1. Two-query sequential flow on single worker', () => {
    it('executes Fastest (flags=0) then Fewest-Transfers (flags=2) sequentially, never in parallel', async () => {
      const callLog: { message: RoutingWorkerIncomingMessage; timestamp: number }[] = [];
      let inFlight = 0;
      let maxConcurrent = 0;

      const mockWorker: RoutingWorkerLike = {
        postMessage: (msg: RoutingWorkerIncomingMessage) => {
          inFlight++;
          if (inFlight > maxConcurrent) maxConcurrent = inFlight;
          const now = Date.now();
          callLog.push({ message: msg, timestamp: now });

          if (msg.type === 'ROUTE') {
            setTimeout(() => {
              inFlight--;
              const segments = msg.profile === 'fastest' ? [directLegA] : [directLegA];
              const outgoing: RoutingWorkerOutgoingMessage = {
                type: 'RESULT',
                segments,
                profile: msg.profile,
                flags: msg.flags,
                queryId: msg.queryId,
              };
              if (mockWorker.onmessage) {
                mockWorker.onmessage({ data: outgoing } as MessageEvent);
              }
            }, 10);
          }
        },
      };

      const result = await executeDualProfileRouting(mockWorker, 101, 303, 28800);

      assert.strictEqual(callLog.length, 2, 'Must execute exactly 2 queries');
      assert.strictEqual(maxConcurrent, 1, 'Max concurrent queries must be 1 (strictly sequential)');

      // Verify Query 1: Fastest
      const q1 = callLog[0].message;
      assert.strictEqual(q1.type, 'ROUTE');
      if (q1.type === 'ROUTE') {
        assert.strictEqual(q1.profile, 'fastest');
        assert.strictEqual(q1.flags, ROUTING_FLAG_NONE);
      }

      // Verify Query 2: Fewest Transfers
      const q2 = callLog[1].message;
      assert.strictEqual(q2.type, 'ROUTE');
      if (q2.type === 'ROUTE') {
        assert.strictEqual(q2.profile, 'fewest_transfers');
        assert.strictEqual(q2.flags, ROUTING_FLAG_AVOID_TRANSFERS);
      }

      assert.deepStrictEqual(result.fastest, [directLegA]);
      assert.deepStrictEqual(result.fewestTransfers, [directLegA]);
    });

    it('reports progress callback through the two sequential stages', async () => {
      const stages: string[] = [];
      const mockWorker: RoutingWorkerLike = {
        postMessage: (msg: RoutingWorkerIncomingMessage) => {
          if (msg.type === 'ROUTE') {
            setTimeout(() => {
              mockWorker.onmessage?.({
                data: {
                  type: 'RESULT',
                  segments: [directLegA],
                  profile: msg.profile,
                  flags: msg.flags,
                  queryId: msg.queryId,
                },
              } as MessageEvent);
            }, 5);
          }
        },
      };

      await executeDualProfileRouting(mockWorker, 101, 303, 28800, {
        onProgress: (stage) => stages.push(stage),
      });

      assert.deepStrictEqual(stages, ['fastest', 'fewest_transfers']);
    });

    it('negative case: halts sequential chain and rejects when query 1 fails', async () => {
      let query2Attempted = false;
      const mockWorker: RoutingWorkerLike = {
        postMessage: (msg: RoutingWorkerIncomingMessage) => {
          if (msg.type === 'ROUTE') {
            if (msg.profile === 'fastest') {
              setTimeout(() => {
                mockWorker.onmessage?.({
                  data: {
                    type: 'ERROR',
                    message: 'WASM heap out of memory',
                    queryId: msg.queryId,
                  },
                } as MessageEvent);
              }, 5);
            } else {
              query2Attempted = true;
            }
          }
        },
      };

      await assert.rejects(
        async () => {
          await executeDualProfileRouting(mockWorker, 101, 303, 28800);
        },
        /WASM heap out of memory/
      );

      assert.strictEqual(query2Attempted, false, 'Query 2 must never run if query 1 fails');
    });

    it('negative case: rejects with timeout when worker hangs on a query', async () => {
      const mockWorker: RoutingWorkerLike = {
        postMessage: () => {
          // Intentionally do not reply to simulate engine hang
        },
      };

      await assert.rejects(
        async () => {
          await executeDualProfileRouting(mockWorker, 101, 303, 28800, { timeoutMs: 30 });
        },
        /Routing query timed out for profile fastest/
      );
    });
  });

  describe('2. Deduplication logic (identical collapse vs differing preservation)', () => {
    it('collapses identical itineraries into exactly 1 card badged with both profiles', () => {
      const fastestItinerary: RoutingSegment[] = [directLegA];
      const fewestItinerary: RoutingSegment[] = [directLegA];

      const ranked = buildRankedItineraries(fastestItinerary, fewestItinerary, 'fastest');

      assert.strictEqual(ranked.length, 1, 'Identical itineraries must collapse to 1 card');
      assert.strictEqual(ranked[0].isDeduped, true);
      assert.deepStrictEqual(ranked[0].profiles, ['fastest', 'fewest_transfers']);
      assert.strictEqual(ranked[0].transferCount, 0);
      assert.strictEqual(ranked[0].durationMinutes, 24);
    });

    it('preserves both cards when itineraries differ in duration and transfer count', () => {
      const fastestItinerary: RoutingSegment[] = [transferLegA1, walkTransfer, transferLegA2]; // 22 min, 1 transfer
      const fewestItinerary: RoutingSegment[] = [directLegA]; // 24 min, 0 transfers

      const ranked = buildRankedItineraries(fastestItinerary, fewestItinerary, 'fastest');

      assert.strictEqual(ranked.length, 2, 'Differing itineraries must render 2 separate cards');
      assert.strictEqual(ranked[0].isDeduped, false);
      assert.strictEqual(ranked[1].isDeduped, false);

      // Ranked with fastest first
      assert.strictEqual(ranked[0].profile, 'fastest');
      assert.strictEqual(ranked[0].durationMinutes, 22);
      assert.strictEqual(ranked[0].transferCount, 1);

      assert.strictEqual(ranked[1].profile, 'fewest_transfers');
      assert.strictEqual(ranked[1].durationMinutes, 24);
      assert.strictEqual(ranked[1].transferCount, 0);
    });

    it('negative case: handles empty itineraries safely without crashing', () => {
      const emptyResults = buildRankedItineraries([], [], 'fastest');
      assert.strictEqual(emptyResults.length, 0);

      const nullResults = buildRankedItineraries(null, null, 'fastest');
      assert.strictEqual(nullResults.length, 0);
    });

    it('handles one profile returning route while other returns empty (partial result)', () => {
      const ranked = buildRankedItineraries([directLegA], [], 'fastest');
      assert.strictEqual(ranked.length, 1);
      assert.strictEqual(ranked[0].profile, 'fastest');
      assert.strictEqual(ranked[0].isDeduped, false);
      assert.deepStrictEqual(ranked[0].profiles, ['fastest']);
    });

    it('negative case: does not dedupe if segments have different departure times or routes', () => {
      const legDiffRoute: RoutingSegment = { ...directLegA, route_id: 99 };
      assert.strictEqual(areItinerariesIdentical([directLegA], [legDiffRoute]), false);

      const legDiffTime: RoutingSegment = { ...directLegA, departure_time: 29000 };
      assert.strictEqual(areItinerariesIdentical([directLegA], [legDiffTime]), false);

      const legDiffStops: RoutingSegment = { ...directLegA, exit_stop_id: 999 };
      assert.strictEqual(areItinerariesIdentical([directLegA], [legDiffStops]), false);
    });
  });

  describe('3. Profile selector state & re-ranking', () => {
    const fastestItinerary: RoutingSegment[] = [transferLegA1, walkTransfer, transferLegA2]; // 22 min, 1 transfer
    const fewestItinerary: RoutingSegment[] = [directLegA]; // 24 min, 0 transfers

    it('ranks fastest as #1 when profile selector is set to "fastest"', () => {
      const ranked = buildRankedItineraries(fastestItinerary, fewestItinerary, 'fastest');
      assert.strictEqual(ranked[0].profile, 'fastest');
      assert.strictEqual(ranked[1].profile, 'fewest_transfers');
    });

    it('re-ranks fewest-transfers as #1 when profile selector is switched to "fewest_transfers"', () => {
      const ranked = buildRankedItineraries(fastestItinerary, fewestItinerary, 'fewest_transfers');
      assert.strictEqual(ranked[0].profile, 'fewest_transfers');
      assert.strictEqual(ranked[1].profile, 'fastest');
    });

    it('keeps single card as #1 in both profile selector states when deduped', () => {
      const rankedFastest = buildRankedItineraries([directLegA], [directLegA], 'fastest');
      assert.strictEqual(rankedFastest.length, 1);
      assert.strictEqual(rankedFastest[0].isDeduped, true);

      const rankedFewest = buildRankedItineraries([directLegA], [directLegA], 'fewest_transfers');
      assert.strictEqual(rankedFewest.length, 1);
      assert.strictEqual(rankedFewest[0].isDeduped, true);
    });
  });

  describe('4. Commuter transfer count & duration human formatting', () => {
    it('accurately counts transit transfers', () => {
      // 1 direct transit leg -> 0 transfers
      assert.strictEqual(countTransfers([directLegA]), 0);

      // 2 transit legs + 1 walk transfer -> 1 transfer
      assert.strictEqual(countTransfers([transferLegA1, walkTransfer, transferLegA2]), 1);

      // 3 transit legs + 2 walk transfers -> 2 transfers
      const thirdLeg: RoutingSegment = { ...directLegA, route_id: 5 };
      assert.strictEqual(
        countTransfers([transferLegA1, walkTransfer, transferLegA2, walkTransfer, thirdLeg]),
        2
      );

      // Walk-only or empty segments -> 0 transfers
      assert.strictEqual(countTransfers([]), 0);
      assert.strictEqual(countTransfers([walkTransfer]), 0);
    });

    it('formats transfer count into human commuter labels', () => {
      assert.strictEqual(formatTransferCount(0), 'No transfers');
      assert.strictEqual(formatTransferCount(1), '1 transfer');
      assert.strictEqual(formatTransferCount(2), '2 transfers');
      assert.strictEqual(formatTransferCount(3), '3 transfers');
    });

    it('formats human durations and satisfies §13.2 rejection criteria (no raw seconds)', () => {
      assert.strictEqual(formatDurationHuman(60), '1 min');
      assert.strictEqual(formatDurationHuman(1440), '24 min');
      assert.strictEqual(formatDurationHuman(3600), '1 hr');
      assert.strictEqual(formatDurationHuman(5400), '1 hr 30 min');

      // Negative check: ensure no raw seconds notation leaks
      const sample = formatDurationHuman(1440);
      assert.strictEqual(sample.includes('1440'), false, 'Raw seconds must not be displayed');
      assert.strictEqual(sample.includes('sec'), false, 'Raw seconds must not be displayed');
    });

    it('formats clock time and arrival time into human strings', () => {
      assert.strictEqual(formatClockTime(28800), '08:00');
      assert.strictEqual(formatClockTime(30240), '08:24');

      assert.strictEqual(formatArrivalTime(28800), '8:00 AM');
      assert.strictEqual(formatArrivalTime(30240), '8:24 AM');
      assert.strictEqual(formatArrivalTime(50400), '2:00 PM'); // 14:00
    });
  });

  describe('5. UI States enumeration & Commuter View contract', () => {
    it('enumerates all 6 required UI states and verifies commuter visible content', () => {
      // 1. Loading state
      const loadingState = getRouteComparisonUIState({
        isRouting: true,
        routeError: null,
        rankedCards: [],
        hasQueried: true,
      });
      assert.strictEqual(loadingState.state, 'loading');
      assert.strictEqual(loadingState.hasCards, false);
      assert.strictEqual(loadingState.userFacingTitle, 'Routing offline trip...');

      // 2. Error state
      const errorState = getRouteComparisonUIState({
        isRouting: false,
        routeError: 'Worker communication timeout',
        rankedCards: [],
        hasQueried: true,
      });
      assert.strictEqual(errorState.state, 'error');
      assert.strictEqual(errorState.hasCards, false);
      assert.match(errorState.userFacingDescription, /Worker communication timeout/);

      // 3. Empty state
      const emptyState = getRouteComparisonUIState({
        isRouting: false,
        routeError: null,
        rankedCards: [],
        hasQueried: true,
      });
      assert.strictEqual(emptyState.state, 'empty');
      assert.strictEqual(emptyState.hasCards, false);
      assert.match(emptyState.userFacingTitle, /No routes found/);

      // 4. One result state
      const singleCard = createRankedItinerary([directLegA], 'fastest', ['fastest'], false);
      const oneResultState = getRouteComparisonUIState({
        isRouting: false,
        routeError: null,
        rankedCards: [singleCard],
        hasQueried: true,
      });
      assert.strictEqual(oneResultState.state, 'one_result');
      assert.strictEqual(oneResultState.hasCards, true);
      assert.strictEqual(oneResultState.cardCount, 1);

      // 5. Two results state
      const card1 = createRankedItinerary([transferLegA1, walkTransfer, transferLegA2], 'fastest');
      const card2 = createRankedItinerary([directLegA], 'fewest_transfers');
      const twoResultsState = getRouteComparisonUIState({
        isRouting: false,
        routeError: null,
        rankedCards: [card1, card2],
        hasQueried: true,
      });
      assert.strictEqual(twoResultsState.state, 'two_results');
      assert.strictEqual(twoResultsState.hasCards, true);
      assert.strictEqual(twoResultsState.cardCount, 2);

      // 6. Deduped state
      const dedupedCard = createRankedItinerary([directLegA], 'fastest', ['fastest', 'fewest_transfers'], true);
      const dedupedState = getRouteComparisonUIState({
        isRouting: false,
        routeError: null,
        rankedCards: [dedupedCard],
        hasQueried: true,
      });
      assert.strictEqual(dedupedState.state, 'deduped');
      assert.strictEqual(dedupedState.hasCards, true);
      assert.strictEqual(dedupedState.cardCount, 1);
      assert.match(dedupedState.userFacingTitle, /Optimal Route/);
    });
  });

  describe('6. Worker Engine profile/flags contract', () => {
    it('creates worker handler accepting flags and echoing profile in RESULT', async () => {
      const messages: RoutingWorkerOutgoingMessage[] = [];
      const fakeWasm = {
        HEAPU8: new Uint8Array(1024),
        HEAP32: new Int32Array(256),
        HEAPF32: new Float32Array(256),
        _allocate_aligned: () => 64,
        _engine_create: () => 1,
        _engine_destroy: () => {},
        _engine_load_timetable: () => true,
        _engine_load_ultra: () => true,
        _engine_load_walk_graph: () => true,
        _engine_compute_journey: () => 0, // returns null result for test
        _engine_free_result: () => {},
        _malloc: () => 128,
        _free: () => {},
      };

      const handler = createRoutingWorkerHandler({
        postMessage: (m) => messages.push(m),
        loadWasm: async () => fakeWasm as any,
        hydrateBinaries: async () => {},
      });

      await handler({ type: 'INIT' });
      assert.strictEqual(messages[0].type, 'READY');

      // Test Fastest (flags=0)
      await handler({
        type: 'ROUTE',
        origin_stop_id: 101,
        dest_stop_id: 303,
        departure_timestamp: 28800,
        profile: 'fastest',
        flags: 0,
        queryId: 'q1',
      });

      assert.strictEqual(messages.length, 2);
      const res1 = messages[1];
      assert.strictEqual(res1.type, 'RESULT');
      if (res1.type === 'RESULT') {
        assert.strictEqual(res1.profile, 'fastest');
        assert.strictEqual(res1.flags, 0);
        assert.strictEqual(res1.queryId, 'q1');
      }

      // Test Fewest Transfers (flags=2)
      await handler({
        type: 'ROUTE',
        origin_stop_id: 101,
        dest_stop_id: 303,
        departure_timestamp: 28800,
        profile: 'fewest_transfers',
        flags: 2,
        queryId: 'q2',
      });

      assert.strictEqual(messages.length, 3);
      const res2 = messages[2];
      assert.strictEqual(res2.type, 'RESULT');
      if (res2.type === 'RESULT') {
        assert.strictEqual(res2.profile, 'fewest_transfers');
        assert.strictEqual(res2.flags, 2);
        assert.strictEqual(res2.queryId, 'q2');
      }
    });
  });

  describe('7. TripPlanner Dual-Profile Wiring & Error Handling Contract', () => {
    it('negative case: halts and rejects cleanly when Query 2 (Fewest-Transfers) fails', async () => {
      const mockWorker: RoutingWorkerLike = {
        postMessage: (msg: RoutingWorkerIncomingMessage) => {
          if (msg.type === 'ROUTE') {
            if (msg.profile === 'fastest') {
              setTimeout(() => {
                mockWorker.onmessage?.({
                  data: {
                    type: 'RESULT',
                    segments: [directLegA],
                    profile: msg.profile,
                    flags: msg.flags,
                    queryId: msg.queryId,
                  },
                } as MessageEvent);
              }, 5);
            } else {
              setTimeout(() => {
                mockWorker.onmessage?.({
                  data: {
                    type: 'ERROR',
                    message: 'Fewest transfers RAPTOR graph corrupted',
                    queryId: msg.queryId,
                  },
                } as MessageEvent);
              }, 5);
            }
          }
        },
      };

      await assert.rejects(
        async () => {
          await executeDualProfileRouting(mockWorker, 101, 303, 28800);
        },
        /Fewest transfers RAPTOR graph corrupted/
      );
    });

    it('coordinates RoutingQueryWatchdog start and stop around dual-profile queries', async () => {
      let watchdogTimedOut = false;
      const watchdog = new RoutingQueryWatchdog(500, () => {
        watchdogTimedOut = true;
      });

      const mockWorker: RoutingWorkerLike = {
        postMessage: (msg: RoutingWorkerIncomingMessage) => {
          if (msg.type === 'ROUTE') {
            setTimeout(() => {
              mockWorker.onmessage?.({
                data: {
                  type: 'RESULT',
                  segments: [directLegA],
                  profile: msg.profile,
                  flags: msg.flags,
                  queryId: msg.queryId,
                },
              } as MessageEvent);
            }, 10);
          }
        },
      };

      watchdog.start();
      assert.strictEqual(watchdog.isRunning, true, 'Watchdog must be active during query');

      const { fastest, fewestTransfers } = await executeDualProfileRouting(
        mockWorker,
        101,
        303,
        28800
      );

      watchdog.stop();
      assert.strictEqual(watchdog.isRunning, false, 'Watchdog must be stopped upon completion');
      assert.strictEqual(watchdogTimedOut, false, 'Watchdog must not fire if queries complete');
      assert.strictEqual(fastest.length, 1);
      assert.strictEqual(fewestTransfers.length, 1);
    });

    it('simulates TripPlanner UI state transitions: empty -> loading -> two_results -> re-rank -> reset', () => {
      // 1. Initial mounted state (no query yet)
      let isRouting = false;
      let routeError: string | null = null;
      let hasQueried = false;
      let fastest: RoutingSegment[] | null = null;
      let fewest: RoutingSegment[] | null = null;
      let activeProfile: 'fastest' | 'fewest_transfers' = 'fastest';

      let cards = buildRankedItineraries(fastest, fewest, activeProfile);
      let state = getRouteComparisonUIState({ isRouting, routeError, rankedCards: cards, hasQueried });
      assert.strictEqual(state.state, 'empty');
      assert.strictEqual(state.hasCards, false);

      // 2. User taps 'Route Trip': isRouting=true, hasQueried=true
      isRouting = true;
      hasQueried = true;
      state = getRouteComparisonUIState({ isRouting, routeError, rankedCards: cards, hasQueried });
      assert.strictEqual(state.state, 'loading');
      assert.strictEqual(state.userFacingTitle, 'Routing offline trip...');

      // 3. Worker returns differing results
      isRouting = false;
      fastest = [transferLegA1, walkTransfer, transferLegA2]; // 22 min, 1 transfer
      fewest = [directLegA]; // 24 min, 0 transfers
      cards = buildRankedItineraries(fastest, fewest, activeProfile);
      state = getRouteComparisonUIState({ isRouting, routeError, rankedCards: cards, hasQueried });
      assert.strictEqual(state.state, 'two_results');
      assert.strictEqual(cards.length, 2);
      assert.strictEqual(cards[0].profile, 'fastest');
      assert.strictEqual(cards[1].profile, 'fewest_transfers');

      // 4. User toggles profile selector to 'fewest_transfers'
      activeProfile = 'fewest_transfers';
      cards = buildRankedItineraries(fastest, fewest, activeProfile);
      assert.strictEqual(cards[0].profile, 'fewest_transfers');
      assert.strictEqual(cards[1].profile, 'fastest');

      // 5. User changes origin input: resetRoutes called
      fastest = null;
      fewest = null;
      routeError = null;
      hasQueried = false;
      cards = buildRankedItineraries(fastest, fewest, activeProfile);
      state = getRouteComparisonUIState({ isRouting, routeError, rankedCards: cards, hasQueried });
      assert.strictEqual(state.state, 'empty');
      assert.strictEqual(cards.length, 0);
    });

    it('negative case: when both profiles yield 0 segments, classifies as empty with no cards', () => {
      const emptyFastest: RoutingSegment[] = [];
      const emptyFewest: RoutingSegment[] = [];
      const cards = buildRankedItineraries(emptyFastest, emptyFewest, 'fastest');
      assert.strictEqual(cards.length, 0);

      const state = getRouteComparisonUIState({
        isRouting: false,
        routeError: null,
        rankedCards: cards,
        hasQueried: true,
      });
      assert.strictEqual(state.state, 'empty');
      assert.strictEqual(state.hasCards, false);
      assert.strictEqual(state.userFacingTitle, 'No routes found');
    });
  });
});
