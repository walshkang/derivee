import { describe, it } from 'node:test';
import assert from 'node:assert';
import { createRequire } from 'node:module';
import {
  isTransferLeg,
  createRoutingWorkerHandler,
  loadWasmModule,
  instantiateDeriveeCore,
  TRIP_TRANSFER,
  ROUTE_TRANSFER,
} from '../routingEngine.ts';
import type { RoutingWorkerOutgoingMessage } from '../../types/routing.ts';

const require = createRequire(import.meta.url);
const DeriveeCoreModule = require('../../../public/wasm/derivee_core.js');

describe('M3b Routing Worker Regression Tests', () => {
  describe('Bug 1: Init failure propagation (no hang on empty or corrupt wasm)', () => {
    it('posts ERROR when fed an empty wasm binary through the init path', async () => {
      const messages: RoutingWorkerOutgoingMessage[] = [];
      const handler = createRoutingWorkerHandler({
        postMessage: (msg) => messages.push(msg),
        loadWasm: () =>
          loadWasmModule({
            factory: DeriveeCoreModule,
            wasmBinary: new Uint8Array(0),
          }),
      });

      // Execute init message through the worker orchestration
      await handler({ type: 'INIT' });

      assert.strictEqual(messages.length, 1, 'Worker must post exactly 1 message');
      assert.strictEqual(messages[0].type, 'ERROR', 'Worker must post ERROR, not hang or post READY');
      if (messages[0].type === 'ERROR') {
        assert.match(
          messages[0].message,
          /BufferSource|empty/i,
          `Expected empty buffer error message, got: ${messages[0].message}`
        );
      }
    });

    it('posts ERROR when fed a corrupt wasm binary through the init path', async () => {
      const messages: RoutingWorkerOutgoingMessage[] = [];
      const handler = createRoutingWorkerHandler({
        postMessage: (msg) => messages.push(msg),
        loadWasm: () =>
          loadWasmModule({
            factory: DeriveeCoreModule,
            wasmBinary: new Uint8Array([0x00, 0x11, 0x22, 0x33]),
          }),
      });

      await handler({ type: 'INIT' });

      assert.strictEqual(messages.length, 1, 'Worker must post exactly 1 message');
      assert.strictEqual(messages[0].type, 'ERROR', 'Worker must post ERROR, not hang or post READY');
      if (messages[0].type === 'ERROR') {
        assert.match(
          messages[0].message,
          /magic word|compile/i,
          `Expected corrupt binary error message, got: ${messages[0].message}`
        );
      }
    });

    it('posts ERROR "engine init timed out" when init does not settle within timeout', async () => {
      const messages: RoutingWorkerOutgoingMessage[] = [];
      const handler = createRoutingWorkerHandler({
        postMessage: (msg) => messages.push(msg),
        initTimeoutMs: 50,
        loadWasm: () => new Promise(() => {}), // simulated hang that never settles
      });

      await handler({ type: 'INIT' });

      assert.strictEqual(messages.length, 1);
      assert.strictEqual(messages[0].type, 'ERROR');
      if (messages[0].type === 'ERROR') {
        assert.strictEqual(messages[0].message, 'engine init timed out');
      }
    });

    it('proves that instantiateDeriveeCore directly rejects instead of hanging on bad binary', async () => {
      let rejected = false;
      try {
        await instantiateDeriveeCore(DeriveeCoreModule, new Uint8Array([0x01, 0x02, 0x03, 0x04]));
      } catch (err: any) {
        rejected = true;
        assert.match(err.message, /magic word|compile/i);
      }
      assert.strictEqual(rejected, true, 'instantiateDeriveeCore must reject, never hang');
    });
  });

  describe('Bug 2: is_transfer mapping alignment with native TimetableStructs.hpp', () => {
    const fixtures = [
      { trip: 0xFFFFFFFF, route: 5, expected: true },
      { trip: 0, route: 0, expected: false },
      { trip: 7, route: 0xFFFF, expected: true },
      { trip: 7, route: 3, expected: false },
    ];

    it('matches native JourneySegment::is_transfer_leg() across all fixtures', () => {
      for (const { trip, route, expected } of fixtures) {
        const actual = isTransferLeg(trip, route);
        assert.strictEqual(
          actual,
          expected,
          `Failed for trip=${trip}, route=${route}: expected ${expected}, got ${actual}`
        );
      }
    });

    it('documents how the pre-fix worker logic would have failed on (trip=0, route=0)', () => {
      // Pre-fix formula: trip === 0 || trip === 0xFFFFFFFF || route === 0 || route === 0xFFFF
      const oldIsTransfer = (trip: number, route: number) =>
        trip === 0 || trip === 0xFFFFFFFF || route === 0 || route === 0xFFFF;

      // The pre-fix formula incorrectly returned true for (trip=0, route=0)
      assert.strictEqual(
        oldIsTransfer(0, 0),
        true,
        'Pre-fix formula mislabeled zero-id legs as transfers'
      );

      // The fixed formula correctly returns false
      assert.strictEqual(
        isTransferLeg(0, 0),
        false,
        'Aligned formula correctly labels zero-id legs as transit, matching native'
      );
    });

    it('matches exact native constants TRIP_TRANSFER and ROUTE_TRANSFER', () => {
      assert.strictEqual(TRIP_TRANSFER, 0xFFFFFFFF);
      assert.strictEqual(ROUTE_TRANSFER, 0xFFFF);
    });
  });
});
