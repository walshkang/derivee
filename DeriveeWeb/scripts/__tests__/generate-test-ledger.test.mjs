import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import {
  parseLedgerTable,
  formatLedgerTable,
  extractScenariosFromReport,
  mergeLedger,
  SEED_SCENARIOS,
} from '../generate-test-ledger.mjs';

describe('Test-Evidence Ledger Generator', () => {
  it('parses existing markdown table correctly', () => {
    const markdown = `# Test-Evidence Ledger

| Scenario | Flow | Harness | Device | Evidence | Updated |
|---|---|---|---|---|---|
| Map mounts to ready | map | ✅ r1 / a1b2c3d | ✅ 2026-10-01 | [report](../report.html) | 2026-10-01 |
| Footer shows build hash | system info | ✅ r1 / a1b2c3d | pending | [report](../report.html) | 2026-10-01 |
`;

    const rows = parseLedgerTable(markdown);
    assert.equal(rows.length, 2);
    assert.deepEqual(rows[0], {
      scenario: 'Map mounts to ready',
      flow: 'map',
      harness: '✅ r1 / a1b2c3d',
      device: '✅ 2026-10-01',
      evidence: '[report](../report.html)',
      updated: '2026-10-01',
    });
    assert.equal(rows[1].device, 'pending');
  });

  it('formats rows into markdown table matching spec schema', () => {
    const rows = [
      {
        scenario: 'Map mounts to ready',
        flow: 'map',
        harness: '✅ r1 / c1',
        device: '✅ 2026-10-01',
        evidence: '[report](rep.html) [shot](shot.png)',
        updated: '2026-10-01',
      },
    ];

    const md = formatLedgerTable(rows);
    assert.match(md, /# Test-Evidence Ledger/);
    assert.match(md, /\| Scenario \| Flow \| Harness \| Device \| Evidence \| Updated \|/);
    assert.match(md, /\| Map mounts to ready \| map \| ✅ r1 \/ c1 \| ✅ 2026-10-01 \| \[report\]\(rep\.html\) \[shot\]\(shot\.png\) \| 2026-10-01 \|/);
  });

  it('extracts scenarios from Playwright-compatible suite format', () => {
    const pwReport = {
      runId: 'r1',
      commit: 'abc1234',
      suites: [
        {
          title: 'Diagnostic Suite',
          specs: [
            {
              title: 'Map mounts to ready',
              ok: true,
              tests: [
                {
                  annotations: [{ type: 'flow', description: 'map' }],
                  results: [
                    {
                      status: 'passed',
                      duration: 1200,
                      attachments: [{ name: 'screenshot', path: '/path/to/shot.png' }],
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

    const scenarios = extractScenariosFromReport(pwReport);
    assert.equal(scenarios.length, 1);
    assert.equal(scenarios[0].name, 'Map mounts to ready');
    assert.equal(scenarios[0].flow, 'map');
    assert.equal(scenarios[0].status, 'passed');
    assert.deepEqual(scenarios[0].screenshots, ['/path/to/shot.png']);
  });

  it('generates initial ledger from report with seed device verdicts', () => {
    const reportData = {
      runId: 'r20261002-113543',
      commit: 'f5fab9a',
      timestamp: '2026-10-02T15:30:00.000Z',
      reportPath: '/home/hatch/workspace/derivee-audits/runs/r20261002-113543/report/index.html',
      scenarios: [
        {
          name: 'Map mounts to ready',
          flow: 'map',
          status: 'passed',
          durationMs: 2500,
          screenshots: ['/home/hatch/workspace/derivee-audits/runs/r20261002-113543/screenshots/map-ready.png'],
        },
        {
          name: 'Cached reload reaches ready',
          flow: 'map',
          status: 'passed',
          durationMs: 1500,
          screenshots: ['/home/hatch/workspace/derivee-audits/runs/r20261002-113543/screenshots/cached-reload.png'],
        },
        {
          name: 'Route cards scroll on swipe, sheet stays put',
          flow: 'trip planning',
          status: 'passed',
          durationMs: 3500,
          screenshots: ['/home/hatch/workspace/derivee-audits/runs/r20261002-113543/screenshots/trip-cards-scrolled.png'],
        },
        {
          name: 'Footer shows build hash',
          flow: 'system info',
          status: 'passed',
          durationMs: 500,
          screenshots: ['/home/hatch/workspace/derivee-audits/runs/r20261002-113543/screenshots/footer-build.png'],
        },
      ],
    };

    const resultMd = mergeLedger('', reportData, {
      ledgerPath: '/home/hatch/workspace/derivee/TEST-LEDGER.md',
    });

    const rows = parseLedgerTable(resultMd);
    assert.equal(rows.length, 4);

    const mapReady = rows.find((r) => r.scenario === 'Map mounts to ready');
    assert.equal(mapReady.flow, 'map');
    assert.equal(mapReady.harness, '✅ r20261002-113543 / f5fab9a');
    assert.equal(mapReady.device, '✅ 2026-10-01');
    assert.match(mapReady.evidence, /\[report\]\(\.\.\/derivee-audits\/runs\/r20261002-113543\/report\/index\.html\)/);
    assert.match(mapReady.evidence, /\[shot\]\(\.\.\/derivee-audits\/runs\/r20261002-113543\/screenshots\/map-ready\.png\)/);
    assert.equal(mapReady.updated, '2026-10-02');

    const cachedReload = rows.find((r) => r.scenario === 'Cached reload reaches ready');
    assert.equal(cachedReload.device, 'pending');
    assert.equal(cachedReload.harness, '✅ r20261002-113543 / f5fab9a');

    const cardScroll = rows.find((r) => r.scenario === 'Route cards scroll on swipe, sheet stays put');
    assert.equal(cardScroll.device, '✅ 2026-10-02');
    assert.equal(cardScroll.harness, '✅ r20261002-113543 / f5fab9a');

    const footer = rows.find((r) => r.scenario === 'Footer shows build hash');
    assert.equal(footer.device, 'pending');
    assert.equal(footer.harness, '✅ r20261002-113543 / f5fab9a');
  });

  it('preserves existing device verdicts across regenerations with passing runs', () => {
    const existingMd = `# Test-Evidence Ledger

| Scenario | Flow | Harness | Device | Evidence | Updated |
|---|---|---|---|---|---|
| Route cards scroll on swipe, sheet stays put | trip planning | ✅ r1 / c1 | ✅ 2026-10-02 | [report](rep1.html) | 2026-10-02 |
`;

    const newReport = {
      runId: 'r2',
      commit: 'c2',
      timestamp: '2026-10-03T10:00:00.000Z',
      scenarios: [
        {
          name: 'Route cards scroll on swipe, sheet stays put',
          flow: 'trip planning',
          status: 'passed',
          screenshots: [],
        },
      ],
    };

    const merged = mergeLedger(existingMd, newReport, {
      ledgerPath: '/home/hatch/workspace/derivee/TEST-LEDGER.md',
    });

    const rows = parseLedgerTable(merged);
    const cardRow = rows.find((r) => r.scenario === 'Route cards scroll on swipe, sheet stays put');
    assert.equal(cardRow.harness, '✅ r2 / c2');
    assert.equal(cardRow.device, '✅ 2026-10-02'); // SURVIVES!
    assert.equal(cardRow.updated, '2026-10-03');
  });

  // NEGATIVE TEST CASE
  it('negative: a new failing harness run does NOT clobber a device ✅', () => {
    const existingMd = `# Test-Evidence Ledger

| Scenario | Flow | Harness | Device | Evidence | Updated |
|---|---|---|---|---|---|
| Route cards scroll on swipe, sheet stays put | trip planning | ✅ r1 / c1 | ✅ 2026-10-02 | [report](rep1.html) | 2026-10-02 |
| Map mounts to ready | map | ✅ r1 / c1 | ✅ 2026-10-01 | [report](rep1.html) | 2026-10-01 |
`;

    const failingReport = {
      runId: 'r-fail',
      commit: 'c-broken',
      timestamp: '2026-10-04T12:00:00.000Z',
      scenarios: [
        {
          name: 'Route cards scroll on swipe, sheet stays put',
          flow: 'trip planning',
          status: 'failed',
          error: { message: 'Touchmove failed to scroll' },
          screenshots: ['/path/to/fail-shot.png'],
        },
      ],
    };

    const merged = mergeLedger(existingMd, failingReport, {
      ledgerPath: '/home/hatch/workspace/derivee/TEST-LEDGER.md',
    });

    const rows = parseLedgerTable(merged);
    const cardRow = rows.find((r) => r.scenario === 'Route cards scroll on swipe, sheet stays put');

    // Harness must reflect the failure
    assert.equal(cardRow.harness, '❌ r-fail / c-broken');
    // Device must NOT be clobbered by failure (neither reset to pending nor changed to ❌)
    assert.equal(cardRow.device, '✅ 2026-10-02');
  });

  it('new scenarios not present in seeds default to pending device verdict', () => {
    const reportData = {
      runId: 'r-new',
      commit: 'c-new',
      timestamp: '2026-10-05T09:00:00.000Z',
      scenarios: [
        {
          name: 'Search autocomplete filters transit stops',
          flow: 'search',
          status: 'passed',
          screenshots: [],
        },
      ],
    };

    const merged = mergeLedger('', reportData, {
      ledgerPath: '/home/hatch/workspace/derivee/TEST-LEDGER.md',
    });

    const rows = parseLedgerTable(merged);
    const searchRow = rows.find((r) => r.scenario === 'Search autocomplete filters transit stops');
    assert.ok(searchRow);
    assert.equal(searchRow.device, 'pending');
    assert.equal(searchRow.harness, '✅ r-new / c-new');
  });

  it('preserves existing scenarios that were not tested in the latest run', () => {
    const existingMd = `# Test-Evidence Ledger

| Scenario | Flow | Harness | Device | Evidence | Updated |
|---|---|---|---|---|---|
| Map mounts to ready | map | ✅ r1 / c1 | ✅ 2026-10-01 | [report](rep1.html) | 2026-10-01 |
| Footer shows build hash | system info | ✅ r1 / c1 | pending | [report](rep1.html) | 2026-10-01 |
`;

    // Report only ran Footer
    const partialReport = {
      runId: 'r2',
      commit: 'c2',
      timestamp: '2026-10-02T16:00:00.000Z',
      scenarios: [
        {
          name: 'Footer shows build hash',
          flow: 'system info',
          status: 'passed',
          screenshots: [],
        },
      ],
    };

    const merged = mergeLedger(existingMd, partialReport, {
      ledgerPath: '/home/hatch/workspace/derivee/TEST-LEDGER.md',
    });

    const rows = parseLedgerTable(merged);
    const mapRow = rows.find((r) => r.scenario === 'Map mounts to ready');
    const footerRow = rows.find((r) => r.scenario === 'Footer shows build hash');

    // Untested scenario preserved
    assert.equal(mapRow.harness, '✅ r1 / c1');
    assert.equal(mapRow.device, '✅ 2026-10-01');

    // Tested scenario updated
    assert.equal(footerRow.harness, '✅ r2 / c2');
  });

  it('supports explicit device verdict overrides via CLI option', () => {
    const reportData = {
      runId: 'r1',
      commit: 'c1',
      timestamp: '2026-10-02T15:00:00.000Z',
      scenarios: [
        {
          name: 'Cached reload reaches ready',
          flow: 'map',
          status: 'passed',
          screenshots: [],
        },
      ],
    };

    const merged = mergeLedger('', reportData, {
      ledgerPath: '/home/hatch/workspace/derivee/TEST-LEDGER.md',
      deviceOverrides: {
        'Cached reload reaches ready': '✅ 2026-10-02 (manual verification)',
      },
    });

    const rows = parseLedgerTable(merged);
    const reloadRow = rows.find((r) => r.scenario === 'Cached reload reaches ready');
    assert.equal(reloadRow.device, '✅ 2026-10-02 (manual verification)');
  });
});
