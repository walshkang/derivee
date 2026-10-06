import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  formatArrivalTime,
  formatTransferCount,
  formatDurationHuman,
} from '../routeComparison.ts';
import { getRouteBadge, createRoutesMap } from '../routeBadge.ts';

describe('Visual Spec Compliance & Departure Modes', () => {
  it('formats hero arrival time with 12-hour AM/PM and zero-padded minutes', () => {
    // 8:20 AM = 8 * 3600 + 20 * 60 = 30000
    assert.equal(formatArrivalTime(30000), '8:20 AM');
    // 3:05 PM = 15 * 3600 + 5 * 60 = 54300
    assert.equal(formatArrivalTime(54300), '3:05 PM');
    // Midnight
    assert.equal(formatArrivalTime(0), '12:00 AM');
    // Noon
    assert.equal(formatArrivalTime(43200), '12:00 PM');
  });

  it('negative case: handles boundary times past 24 hours cleanly', () => {
    // 25:15 -> wraps to 1:15 AM
    const pastMidnight = 25 * 3600 + 15 * 60;
    assert.equal(formatArrivalTime(pastMidnight), '1:15 AM');
  });

  it('formats commuter glance line items with human labels', () => {
    assert.equal(formatTransferCount(0), 'No transfers');
    assert.equal(formatTransferCount(1), '1 transfer');
    assert.equal(formatTransferCount(3), '3 transfers');

    assert.equal(formatDurationHuman(45 * 60), '45 min');
    assert.equal(formatDurationHuman(75 * 60), '1 hr 15 min');
  });

  it('strict FC-2 compliance: getRouteBadge never leaks internal integer IDs', () => {
    const routesMap = createRoutesMap({
      'L': { shortName: 'L', color: 'A7A9AC', textColor: '000000' },
      '2': { shortName: '2', color: 'EE352E', textColor: 'FFFFFF' },
    });

    // Valid route resolves
    const lBadge = getRouteBadge('L', routesMap);
    assert.ok(lBadge);
    assert.equal(lBadge.label, 'L');
    assert.equal(lBadge.backgroundColor, '#A7A9AC');

    // Unknown raw ID returns null, NEVER a raw ID badge
    const unknownBadge = getRouteBadge('99999', routesMap);
    assert.equal(unknownBadge, null);

    const emptyBadge = getRouteBadge('', routesMap);
    assert.equal(emptyBadge, null);
  });
});
