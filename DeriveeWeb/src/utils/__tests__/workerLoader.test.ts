import { describe, it } from 'node:test';
import assert from 'node:assert';
import { createWorkerWithRetry } from '../workerLoader.ts';

describe('Worker Loader with Retry & Diagnostic Contract', () => {
  it('Worker instantiation fails with WebKit "Load failed" -> retries with bounded backoff and names resource in Diagnostic', async () => {
    let callCount = 0;
    const workerFactory = () => {
      callCount++;
      throw new TypeError('Load failed');
    };

    const sleepCalls: number[] = [];
    const mockSleep = async (ms: number) => {
      sleepCalls.push(ms);
    };

    const workerUrl = new URL('http://localhost/assets/basemap-installer.worker.js');

    await assert.rejects(
      async () => {
        await createWorkerWithRetry(workerFactory, workerUrl, {
          maxRetries: 2,
          retryDelayMs: 10,
          sleep: mockSleep,
        });
      },
      (err: Error) => {
        assert.ok(
          err.message.includes('/assets/basemap-installer.worker.js'),
          `Error message must explicitly name the worker resource URL (got "${err.message}")`
        );
        assert.notStrictEqual(
          err.message,
          'Load failed',
          'Error must not surface raw engine message "Load failed" verbatim'
        );
        return true;
      }
    );

    assert.strictEqual(callCount, 3, 'Must attempt initial creation plus 2 retries (total 3)');
    assert.deepStrictEqual(sleepCalls, [10, 20], 'Must back off exponentially between retries');
  });

  it('Negative case: transient "Load failed" on first attempt recovers on retry -> returns Worker without error', async () => {
    let callCount = 0;
    const mockWorkerInstance = { terminate: () => {} } as unknown as Worker;

    const workerFactory = () => {
      callCount++;
      if (callCount === 1) {
        throw new TypeError('Load failed');
      }
      return mockWorkerInstance;
    };

    const workerUrl = new URL('http://localhost/assets/basemap-installer.worker.js');

    const worker = await createWorkerWithRetry(workerFactory, workerUrl, {
      maxRetries: 2,
      retryDelayMs: 10,
    });

    assert.strictEqual(worker, mockWorkerInstance, 'Must return the created worker instance');
    assert.strictEqual(callCount, 2, 'Should succeed on second attempt');
  });

  it('Negative case: healthy worker creation succeeds on initial attempt without retries', async () => {
    let callCount = 0;
    const mockWorkerInstance = { terminate: () => {} } as unknown as Worker;

    const workerFactory = () => {
      callCount++;
      return mockWorkerInstance;
    };

    const workerUrl = new URL('http://localhost/assets/basemap-installer.worker.js');

    const worker = await createWorkerWithRetry(workerFactory, workerUrl, {
      maxRetries: 2,
    });

    assert.strictEqual(worker, mockWorkerInstance);
    assert.strictEqual(callCount, 1, 'Should not retry when first attempt succeeds');
  });
});
