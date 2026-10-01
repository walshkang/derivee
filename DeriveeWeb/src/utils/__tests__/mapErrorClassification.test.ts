import { describe, it } from 'node:test';
import assert from 'node:assert';
import { isFatalMapError, formatMapWorkerError } from '../mapErrorClassification.ts';

describe('Map Error Classification Tests', () => {
  it('classifies missing glyphs 404 as recoverable (not fatal)', () => {
    const err = new Error('Could not load glyphs for Noto Sans Regular: status 404');
    assert.strictEqual(isFatalMapError(err), false);
  });

  it('classifies missing tile 404 as recoverable', () => {
    const err = new Error('Could not load tile: status 404');
    assert.strictEqual(isFatalMapError(err), false);
  });

  it('classifies generic missing glyphs message as recoverable', () => {
    const err = new Error('Could not load glyphs');
    assert.strictEqual(isFatalMapError(err), false);
  });

  it('classifies Error with status property 404 as recoverable', () => {
    const err: any = new Error('Not found');
    err.status = 404;
    assert.strictEqual(isFatalMapError(err), false);
  });

  it('classifies WebGL context lost as fatal', () => {
    const err = new Error('WebGL context lost');
    assert.strictEqual(isFatalMapError(err), true);
  });

  it('classifies undefined error as not fatal (failsafe)', () => {
    assert.strictEqual(isFatalMapError(undefined), false);
  });

  it('classifies arbitrary unexpected error as fatal', () => {
    const err = new Error('Cannot read properties of null (reading "length")');
    assert.strictEqual(isFatalMapError(err), true);
  });
});

describe('formatMapWorkerError Tests', () => {
  const TEST_WORKER_URL = '/assets/maplibre-gl-worker-test.js';

  it('positive: appends worker URL when error mentions worker', () => {
    const err = new Error('Worker initialization failed');
    const formatted = formatMapWorkerError(err, TEST_WORKER_URL);
    assert.strictEqual(
      formatted.message,
      `Worker initialization failed (Worker URL: ${TEST_WORKER_URL})`
    );
  });

  it('negative: leaves non-worker error untouched', () => {
    const err = new Error('WebGL context lost');
    const formatted = formatMapWorkerError(err, TEST_WORKER_URL);
    assert.strictEqual(formatted.message, 'WebGL context lost');
    assert.strictEqual(formatted, err, 'Original Error instance must be returned untouched');
  });

  it('negative: does not duplicate worker URL if already present in message', () => {
    const err = new Error(`Failed to load worker (Worker URL: ${TEST_WORKER_URL})`);
    const formatted = formatMapWorkerError(err, TEST_WORKER_URL);
    assert.strictEqual(
      formatted.message,
      `Failed to load worker (Worker URL: ${TEST_WORKER_URL})`
    );
    assert.strictEqual(formatted, err, 'Should return original Error instance without duplicating URL');
  });

  it('negative: leaves error untouched if attemptedWorkerUrl is empty string', () => {
    const err = new Error('worker failed to start');
    const formatted = formatMapWorkerError(err, '');
    assert.strictEqual(formatted.message, 'worker failed to start');
    assert.strictEqual(formatted, err);
  });

  it('positive: converts non-Error object with worker message and appends URL', () => {
    const errObj = { message: 'Worker script 404' };
    const formatted = formatMapWorkerError(errObj, TEST_WORKER_URL);
    assert.ok(formatted instanceof Error);
    assert.strictEqual(
      formatted.message,
      `Worker script 404 (Worker URL: ${TEST_WORKER_URL})`
    );
  });

  it('negative: converts non-Error object without worker message without appending URL', () => {
    const errObj = { message: 'Failed to compile shader' };
    const formatted = formatMapWorkerError(errObj, TEST_WORKER_URL);
    assert.ok(formatted instanceof Error);
    assert.strictEqual(formatted.message, 'Failed to compile shader');
  });

  it('positive: formats primitive string error mentioning worker with URL', () => {
    const strErr = 'Worker thread crashed';
    const formatted = formatMapWorkerError(strErr, TEST_WORKER_URL);
    assert.ok(formatted instanceof Error);
    assert.strictEqual(
      formatted.message,
      `Worker thread crashed (Worker URL: ${TEST_WORKER_URL})`
    );
  });

  it('negative: handles null/undefined error gracefully with fallback message', () => {
    const formattedNull = formatMapWorkerError(null, TEST_WORKER_URL);
    assert.ok(formattedNull instanceof Error);
    assert.strictEqual(formattedNull.message, 'Map error');

    const formattedUndef = formatMapWorkerError(undefined, TEST_WORKER_URL);
    assert.ok(formattedUndef instanceof Error);
    assert.strictEqual(formattedUndef.message, 'Map error');
  });
});

