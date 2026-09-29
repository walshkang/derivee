import { describe, it } from 'node:test';
import assert from 'node:assert';
import { isFatalMapError } from '../mapErrorClassification.ts';

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
