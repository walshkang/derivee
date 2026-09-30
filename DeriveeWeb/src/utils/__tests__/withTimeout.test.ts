import { describe, it } from 'node:test';
import assert from 'node:assert';
import { withTimeout } from '../withTimeout.ts';

describe('withTimeout Utility Tests', () => {
  it('resolves value when wrapped promise resolves before timeout', async () => {
    const result = await withTimeout(
      Promise.resolve('success'),
      50,
      'Timed out'
    );
    assert.strictEqual(result, 'success');
  });

  it('rejects with timeout message when promise never settles (hangs)', async () => {
    const neverSettling = new Promise<string>(() => {});
    await assert.rejects(
      async () => {
        await withTimeout(neverSettling, 20, 'Operation timed out');
      },
      {
        name: 'Error',
        message: 'Operation timed out',
      }
    );
  });

  it('propagates underlying promise rejection when it fails before timeout', async () => {
    const failing = Promise.reject(new Error('Underlying network failure'));
    await assert.rejects(
      async () => {
        await withTimeout(failing, 50, 'Operation timed out');
      },
      {
        name: 'Error',
        message: 'Underlying network failure',
      }
    );
  });
});
