#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import child_process from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const SEED_SCENARIOS = {
  'Map mounts to ready': {
    flow: 'map',
    device: '✅ 2026-10-01',
  },
  'Cached reload reaches ready': {
    flow: 'map',
    device: 'pending',
  },
  'Route cards scroll on swipe, sheet stays put': {
    flow: 'trip planning',
    device: '✅ 2026-10-02',
  },
  'Footer shows build hash': {
    flow: 'system info',
    device: 'pending',
  },
};

/**
 * Parses markdown table rows from TEST-LEDGER.md.
 */
export function parseLedgerTable(markdown) {
  if (!markdown || typeof markdown !== 'string') return [];
  const lines = markdown.split('\n');
  const rows = [];
  let inTable = false;

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) {
      if (inTable) inTable = false;
      continue;
    }

    const cells = trimmed
      .slice(1, -1)
      .split('|')
      .map((c) => c.trim());

    if (cells.length < 6) continue;

    // Header line detection
    if (cells[0].toLowerCase() === 'scenario' && cells[1].toLowerCase() === 'flow') {
      inTable = true;
      continue;
    }

    // Separator line detection (e.g. |---|---|...)
    if (cells[0].startsWith('---') || cells[0].startsWith(':---')) {
      continue;
    }

    if (inTable) {
      rows.push({
        scenario: cells[0],
        flow: cells[1],
        harness: cells[2],
        device: cells[3],
        evidence: cells[4],
        updated: cells[5],
      });
    }
  }

  return rows;
}

/**
 * Formats ledger rows into the spec-defined markdown table.
 */
export function formatLedgerTable(rows) {
  const header = [
    '# Test-Evidence Ledger',
    '',
    '| Scenario | Flow | Harness | Device | Evidence | Updated |',
    '|---|---|---|---|---|---|',
  ];

  const body = rows.map((r) => {
    return `| ${r.scenario} | ${r.flow} | ${r.harness} | ${r.device} | ${r.evidence} | ${r.updated} |`;
  });

  return `${header.join('\n')}\n${body.join('\n')}\n`;
}

/**
 * Extracts normalized scenarios from a Playwright JSON report.
 */
export function extractScenariosFromReport(reportData, reportFilePath = null) {
  if (!reportData) return [];

  const reportDir = reportFilePath ? path.dirname(reportFilePath) : null;
  const reportHtmlDefault = reportDir ? path.join(reportDir, 'index.html') : null;

  // Direct format emitted by diagnostic-harness
  if (Array.isArray(reportData.scenarios) && reportData.scenarios.length > 0) {
    return reportData.scenarios.map((s) => ({
      name: s.name || s.title,
      flow: s.flow || 'unknown',
      status: s.status === 'passed' ? 'passed' : 'failed',
      durationMs: s.durationMs || 0,
      screenshots: Array.isArray(s.screenshots) ? s.screenshots : [],
      reportHtml: reportData.reportPath || reportHtmlDefault,
    }));
  }

  // Playwright suites/specs format
  const scenarios = [];
  function walkSuite(suite) {
    if (Array.isArray(suite.suites)) {
      for (const sub of suite.suites) walkSuite(sub);
    }
    if (Array.isArray(suite.specs)) {
      for (const spec of suite.specs) {
        const title = spec.title;
        let flow = 'unknown';
        let status = spec.ok ? 'passed' : 'failed';
        let durationMs = 0;
        const screenshots = [];

        if (Array.isArray(spec.tests)) {
          for (const test of spec.tests) {
            if (Array.isArray(test.annotations)) {
              const flowAnn = test.annotations.find((a) => a.type === 'flow');
              if (flowAnn) flow = flowAnn.description;
            }
            if (Array.isArray(test.results)) {
              for (const res of test.results) {
                if (res.status) status = res.status === 'passed' ? 'passed' : 'failed';
                if (res.duration) durationMs += res.duration;
                if (Array.isArray(res.attachments)) {
                  for (const att of res.attachments) {
                    if (att.path) screenshots.push(att.path);
                  }
                }
              }
            }
          }
        }

        scenarios.push({
          name: title,
          flow,
          status,
          durationMs,
          screenshots,
          reportHtml: reportData.reportPath || reportHtmlDefault,
        });
      }
    }
  }

  if (Array.isArray(reportData.suites)) {
    for (const suite of reportData.suites) walkSuite(suite);
  }

  return scenarios;
}

/**
 * Finds the latest Playwright JSON report under audits runs directory.
 */
export function findLatestReport(runsDir) {
  if (!fs.existsSync(runsDir)) return null;

  const entries = fs.readdirSync(runsDir, { withFileTypes: true });
  const candidates = [];

  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name.startsWith('.')) continue;
    const runDir = path.join(runsDir, entry.name);

    // Look for report/report.json or report.json
    const cand1 = path.join(runDir, 'report', 'report.json');
    if (fs.existsSync(cand1)) {
      candidates.push({ path: cand1, mtimeMs: fs.statSync(cand1).mtimeMs });
      continue;
    }
    const cand2 = path.join(runDir, 'report.json');
    if (fs.existsSync(cand2)) {
      candidates.push({ path: cand2, mtimeMs: fs.statSync(cand2).mtimeMs });
    }
  }

  if (candidates.length === 0) return null;
  candidates.sort((a, b) => b.mtimeMs - a.mtimeMs);
  return candidates[0].path;
}

/**
 * Merges previous ledger markdown with new test report results.
 * Preserves Device verdicts across all regenerations.
 */
export function mergeLedger(existingMarkdown, reportData, options = {}) {
  const ledgerPath = options.ledgerPath || path.resolve(__dirname, '../../TEST-LEDGER.md');
  const ledgerDir = path.dirname(ledgerPath);
  const reportFilePath = options.reportFilePath || null;
  const seedScenarios = options.seedScenarios || SEED_SCENARIOS;
  const deviceOverrides = options.deviceOverrides || {};

  const existingRows = parseLedgerTable(existingMarkdown);
  const existingMap = new Map();
  for (const row of existingRows) {
    existingMap.set(row.scenario, row);
  }

  const reportScenarios = extractScenariosFromReport(reportData, reportFilePath);
  const reportMap = new Map();
  for (const s of reportScenarios) {
    reportMap.set(s.name, s);
  }

  const runId = reportData.runId || 'unknown';
  const commit = reportData.commit || 'unknown';
  const dateStr = options.runDate ||
    (reportData.timestamp ? reportData.timestamp.slice(0, 10) : new Date().toISOString().slice(0, 10));

  // Determine overall ordered scenario keys:
  // 1. Seed scenarios order
  // 2. Any additional scenarios already in existing ledger
  // 3. Any additional scenarios from report
  const orderedKeys = [];
  const added = new Set();

  for (const key of Object.keys(seedScenarios)) {
    if (!added.has(key)) {
      orderedKeys.push(key);
      added.add(key);
    }
  }
  for (const row of existingRows) {
    if (!added.has(row.scenario)) {
      orderedKeys.push(row.scenario);
      added.add(row.scenario);
    }
  }
  for (const s of reportScenarios) {
    if (!added.has(s.name)) {
      orderedKeys.push(s.name);
      added.add(s.name);
    }
  }

  const mergedRows = [];

  for (const name of orderedKeys) {
    const existing = existingMap.get(name);
    const fromReport = reportMap.get(name);
    const seed = seedScenarios[name];

    // Flow determination
    const flow = (fromReport && fromReport.flow !== 'unknown' ? fromReport.flow : null) ||
      (existing ? existing.flow : null) ||
      (seed ? seed.flow : 'unknown');

    // Device verdict determination:
    // 1. Explicit override from CLI options
    // 2. Existing ledger device verdict (SURVIVES ANY REGENERATION, EVEN FAILING RUNS)
    // 3. Seed scenario default
    // 4. Fallback 'pending'
    let device = 'pending';
    if (deviceOverrides[name]) {
      device = deviceOverrides[name];
    } else if (existing && existing.device) {
      device = existing.device;
    } else if (seed && seed.device) {
      device = seed.device;
    }

    // Harness verdict & evidence determination
    let harness = existing ? existing.harness : 'pending';
    let evidence = existing ? existing.evidence : '-';
    let updated = existing ? existing.updated : dateStr;

    if (fromReport) {
      const statusIcon = fromReport.status === 'passed' ? '✅' : '❌';
      harness = `${statusIcon} ${runId} / ${commit}`;
      updated = dateStr;

      // Build evidence links relative to ledger file location
      const links = [];
      const reportHtml = fromReport.reportHtml || (reportFilePath ? path.join(path.dirname(reportFilePath), 'index.html') : null);
      if (reportHtml && fs.existsSync(reportHtml)) {
        const relReport = path.relative(ledgerDir, reportHtml);
        links.push(`[report](${relReport})`);
      } else if (reportHtml) {
        const relReport = path.relative(ledgerDir, reportHtml);
        links.push(`[report](${relReport})`);
      }

      if (Array.isArray(fromReport.screenshots) && fromReport.screenshots.length > 0) {
        if (fromReport.screenshots.length === 1) {
          const relShot = path.relative(ledgerDir, fromReport.screenshots[0]);
          links.push(`[shot](${relShot})`);
        } else {
          fromReport.screenshots.forEach((shotPath, idx) => {
            const relShot = path.relative(ledgerDir, shotPath);
            links.push(`[shot ${idx + 1}](${relShot})`);
          });
        }
      }

      if (links.length > 0) {
        evidence = links.join(' ');
      }
    }

    mergedRows.push({
      scenario: name,
      flow,
      harness,
      device,
      evidence,
      updated,
    });
  }

  return formatLedgerTable(mergedRows);
}

/**
 * Main CLI execution logic.
 */
export function generateTestLedger(args = process.argv.slice(2)) {
  const repoRoot = path.resolve(__dirname, '../..');
  const auditsDir = process.env.AUDITS_DIR || path.resolve(repoRoot, '../derivee-audits');
  const runsDir = path.join(auditsDir, 'runs');

  let reportPath = null;
  let ledgerPath = path.resolve(repoRoot, 'TEST-LEDGER.md');
  let runId = null;
  let seedFile = null;
  const deviceOverrides = {};
  let dryRun = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--report' && args[i + 1]) {
      reportPath = path.resolve(args[i + 1]);
      i++;
    } else if ((args[i] === '--ledger' || args[i] === '--out') && args[i + 1]) {
      ledgerPath = path.resolve(args[i + 1]);
      i++;
    } else if (args[i] === '--run-id' && args[i + 1]) {
      runId = args[i + 1];
      i++;
    } else if (args[i] === '--seed-file' && args[i + 1]) {
      seedFile = path.resolve(args[i + 1]);
      i++;
    } else if (args[i] === '--device' && args[i + 1]) {
      const eqIdx = args[i + 1].indexOf('=');
      if (eqIdx > 0) {
        const sc = args[i + 1].slice(0, eqIdx).trim();
        const vd = args[i + 1].slice(eqIdx + 1).trim();
        deviceOverrides[sc] = vd;
      }
      i++;
    } else if (args[i] === '--dry-run') {
      dryRun = true;
    }
  }

  let seedScenarios = { ...SEED_SCENARIOS };
  if (seedFile && fs.existsSync(seedFile)) {
    try {
      const customSeeds = JSON.parse(fs.readFileSync(seedFile, 'utf8'));
      seedScenarios = { ...seedScenarios, ...customSeeds };
    } catch (e) {
      console.warn(`[Ledger] Warning: Failed to parse seed-file ${seedFile}: ${e.message}`);
    }
  }

  // If reportPath not specified, find latest
  if (!reportPath) {
    if (runId) {
      const cand = path.join(runsDir, runId, 'report', 'report.json');
      if (fs.existsSync(cand)) {
        reportPath = cand;
      } else {
        const candAlt = path.join(runsDir, runId, 'report.json');
        if (fs.existsSync(candAlt)) reportPath = candAlt;
      }
    }
    if (!reportPath) {
      reportPath = findLatestReport(runsDir);
    }
  }

  if (!reportPath || !fs.existsSync(reportPath)) {
    console.error(`[Ledger] Error: No Playwright JSON report found at ${reportPath || runsDir}`);
    process.exit(1);
  }

  console.log(`[Ledger] Reading report: ${reportPath}`);
  const reportData = JSON.parse(fs.readFileSync(reportPath, 'utf8'));

  let existingMarkdown = '';
  if (fs.existsSync(ledgerPath)) {
    console.log(`[Ledger] Merging over existing ledger: ${ledgerPath}`);
    existingMarkdown = fs.readFileSync(ledgerPath, 'utf8');
  } else {
    console.log(`[Ledger] Initializing new ledger at: ${ledgerPath}`);
  }

  const updatedMarkdown = mergeLedger(existingMarkdown, reportData, {
    ledgerPath,
    reportFilePath: reportPath,
    seedScenarios,
    deviceOverrides,
  });

  if (dryRun) {
    console.log('\n--- DRY RUN LEDGER OUTPUT ---\n');
    console.log(updatedMarkdown);
  } else {
    fs.writeFileSync(ledgerPath, updatedMarkdown, 'utf8');
    console.log(`[Ledger] Successfully wrote ${ledgerPath}`);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  generateTestLedger();
}
