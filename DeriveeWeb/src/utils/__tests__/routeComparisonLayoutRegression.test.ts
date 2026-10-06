import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const SRC_DIR = path.resolve(__dirname, '../..');
const INDEX_CSS_PATH = path.join(SRC_DIR, 'index.css');
const DIST_DIR = path.resolve(__dirname, '../../../dist');
const ASSETS_DIR = path.join(DIST_DIR, 'assets');

export interface ParsedRule {
  selector: string;
  declarations: Map<string, string>;
  raw: string;
}

/**
 * Parses CSS content into discrete rules with their declaration maps.
 * Handles comments, nested @media/@supports queries, and multi-line selectors.
 */
export function parseCssRules(css: string): ParsedRule[] {
  const clean = css.replace(/\/\*[\s\S]*?\*\//g, '');
  const rules: ParsedRule[] = [];

  let i = 0;
  while (i < clean.length) {
    const openBrace = clean.indexOf('{', i);
    if (openBrace === -1) break;

    const header = clean.slice(i, openBrace).trim();
    let depth = 1;
    let j = openBrace + 1;
    while (j < clean.length && depth > 0) {
      if (clean[j] === '{') depth++;
      else if (clean[j] === '}') depth--;
      j++;
    }
    const body = clean.slice(openBrace + 1, j - 1);

    if (header.startsWith('@media') || header.startsWith('@supports')) {
      rules.push(...parseCssRules(body));
    } else if (!header.startsWith('@')) {
      const declarations = new Map<string, string>();
      const declPairs = body.split(';');
      for (const pair of declPairs) {
        const colonIdx = pair.indexOf(':');
        if (colonIdx !== -1) {
          const prop = pair.slice(0, colonIdx).trim().toLowerCase();
          const val = pair.slice(colonIdx + 1).trim();
          if (prop) {
            declarations.set(prop, val);
          }
        }
      }
      rules.push({
        selector: header,
        declarations,
        raw: clean.slice(i, j).trim(),
      });
    }

    i = j;
  }

  return rules;
}

/**
 * Asserts that the given parsed CSS rules contain a .route-comparison-container rule
 * with explicit `flex-shrink: 0` to prevent flex items containing scroll containers
 * from squishing down to zero height in .trip-planner-card.
 */
export function assertRouteComparisonFlexShrink(rules: ParsedRule[]): void {
  const rule = rules.find((r) => r.selector === '.route-comparison-container');
  if (!rule) {
    throw new Error('Rule .route-comparison-container not found in stylesheet');
  }
  const flexShrink = rule.declarations.get('flex-shrink');
  if (flexShrink !== '0') {
    throw new Error(
      `Expected .route-comparison-container to declare "flex-shrink: 0", but got "${flexShrink ?? 'undefined'}"`
    );
  }
}

describe('Screen 4B Route Comparison Layout & flex-shrink Regression Tests', () => {
  const cssContent = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
  const allRules = parseCssRules(cssContent);

  describe('Source stylesheet verification (src/index.css)', () => {
    it('.route-comparison-container exists and declares flex-shrink: 0', () => {
      const rule = allRules.find((r) => r.selector === '.route-comparison-container');
      assert.ok(rule, '.route-comparison-container rule must exist in src/index.css');
      assert.strictEqual(
        rule.declarations.get('flex-shrink'),
        '0',
        '.route-comparison-container must declare flex-shrink: 0 to prevent collapsing inside scrollable trip planner card'
      );
      assert.strictEqual(
        rule.declarations.get('display'),
        'flex',
        '.route-comparison-container must be display: flex'
      );
      assert.strictEqual(
        rule.declarations.get('flex-direction'),
        'column',
        '.route-comparison-container must be flex-direction: column'
      );
    });

    it('assertRouteComparisonFlexShrink validator passes on current src/index.css', () => {
      assert.doesNotThrow(() => {
        assertRouteComparisonFlexShrink(allRules);
      });
    });

    it('negative case: pre-fix fixture missing flex-shrink fails validation', () => {
      const preFixFixture = `
        .route-comparison-container {
          display: flex;
          flex-direction: column;
          gap: 12px;
          width: 100%;
          margin-top: 10px;
        }
      `;
      const fixtureRules = parseCssRules(preFixFixture);
      assert.throws(
        () => assertRouteComparisonFlexShrink(fixtureRules),
        /Expected \.route-comparison-container to declare "flex-shrink: 0", but got "undefined"/
      );
    });

    it('negative case: fixture with default flex-shrink: 1 fails validation', () => {
      const flexShrinkOneFixture = `
        .route-comparison-container {
          display: flex;
          flex-direction: column;
          flex-shrink: 1;
        }
      `;
      const fixtureRules = parseCssRules(flexShrinkOneFixture);
      assert.throws(
        () => assertRouteComparisonFlexShrink(fixtureRules),
        /Expected \.route-comparison-container to declare "flex-shrink: 0", but got "1"/
      );
    });

    it('negative case: fixture completely missing .route-comparison-container fails validation', () => {
      const missingRuleFixture = `
        .trip-planner-card {
          overflow-y: auto;
        }
      `;
      const fixtureRules = parseCssRules(missingRuleFixture);
      assert.throws(
        () => assertRouteComparisonFlexShrink(fixtureRules),
        /Rule \.route-comparison-container not found in stylesheet/
      );
    });
  });

  describe('Build output asset verification (emitted dist stylesheet contract)', () => {
    it('confirms dist/assets contains emitted CSS bundle and includes flex-shrink:0 on .route-comparison-container', () => {
      if (!fs.existsSync(DIST_DIR) || !fs.existsSync(ASSETS_DIR)) {
        return;
      }

      const assetFiles = fs.readdirSync(ASSETS_DIR);
      const cssFile = assetFiles.find((f) => f.startsWith('index-') && f.endsWith('.css'));
      assert.ok(cssFile, 'Main index-*.css bundle should exist in dist/assets/');

      const distCssContent = fs.readFileSync(path.join(ASSETS_DIR, cssFile), 'utf8');

      // Check minified / emitted rule for .route-comparison-container
      // Minified CSS compresses whitespace, e.g. .route-comparison-container{...flex-shrink:0...}
      const match = distCssContent.match(/\.route-comparison-container\s*\{([^}]+)\}/);
      assert.ok(match, '.route-comparison-container rule must exist in emitted dist CSS bundle');
      const body = match[1];
      assert.ok(
        body.includes('flex-shrink:0') || body.includes('flex-shrink: 0'),
        `Emitted .route-comparison-container in dist must contain flex-shrink:0, found: ${body}`
      );
    });

    it('negative case: verifies fabricated css class does not exist in dist css', () => {
      if (!fs.existsSync(DIST_DIR) || !fs.existsSync(ASSETS_DIR)) {
        return;
      }
      const assetFiles = fs.readdirSync(ASSETS_DIR);
      const cssFile = assetFiles.find((f) => f.startsWith('index-') && f.endsWith('.css'));
      if (!cssFile) return;

      const distCssContent = fs.readFileSync(path.join(ASSETS_DIR, cssFile), 'utf8');
      assert.strictEqual(
        distCssContent.includes('.fabricated-nonexistent-class-xyz'),
        false,
        'Fabricated selector must not exist in emitted dist stylesheet'
      );
    });
  });
});
