import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SRC_DIR = path.resolve(__dirname, '../..');
const INDEX_CSS_PATH = path.join(SRC_DIR, 'index.css');

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
 * Determines whether a CSS rule can be a flex item.
 * An element can be a flex item if it is in-flow (not absolute or fixed position).
 * Declaring flex properties explicitly (e.g. flex: 1) or being an in-flow component
 * in a flex layout hierarchy makes it a flex item subject to min-height auto expansion.
 */
export function canBeFlexItem(rule: ParsedRule): boolean {
  const position = rule.declarations.get('position')?.toLowerCase();
  if (position === 'absolute' || position === 'fixed') {
    return false;
  }
  return true;
}

/**
 * Finds all rules with overflow-y: auto|scroll that can be flex items but do NOT
 * declare min-height: 0.
 */
export function findFlexOverflowRulesMissingMinHeight(rules: ParsedRule[]): ParsedRule[] {
  const failing: ParsedRule[] = [];
  for (const rule of rules) {
    const overflowY = rule.declarations.get('overflow-y')?.toLowerCase();
    const overflow = rule.declarations.get('overflow')?.toLowerCase();
    const hasYOverflow =
      (overflowY && (overflowY.includes('auto') || overflowY.includes('scroll'))) ||
      (overflow && (overflow.includes('auto') || overflow.includes('scroll')));

    if (hasYOverflow && canBeFlexItem(rule)) {
      const minHeight = rule.declarations.get('min-height');
      // Must declare min-height: 0 (or 0px, 0%, etc.) to prevent flexbox auto-height expansion bug
      if (!minHeight || !/^0(px|%|em|rem)?$/.test(minHeight.trim())) {
        failing.push(rule);
      }
    }
  }
  return failing;
}

/**
 * Asserts that all flex item rules with overflow-y: auto|scroll declare min-height: 0.
 */
export function assertFlexOverflowRulesHaveMinHeight(rules: ParsedRule[]): void {
  const failing = findFlexOverflowRulesMissingMinHeight(rules);
  if (failing.length > 0) {
    const selectors = failing.map((r) => r.selector.replace(/\s+/g, ' ')).join(', ');
    throw new Error(
      `Found flex item rules with overflow-y: auto|scroll missing min-height: 0: ${selectors}`
    );
  }
}

describe('Scroll-Chain Flex Min-Height Guard', () => {
  const cssContent = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
  const allRules = parseCssRules(cssContent);

  it('parses CSS rules from src/index.css successfully', () => {
    assert.ok(allRules.length > 0, 'Should parse non-empty list of CSS rules');
    const bodyRule = allRules.find((r) => r.selector === '.app-content-body');
    assert.ok(bodyRule, '.app-content-body rule must exist');
  });

  it('validates every rule in src/index.css with overflow-y: auto|scroll that can be a flex item declares min-height: 0', () => {
    const failing = findFlexOverflowRulesMissingMinHeight(allRules);
    assert.deepStrictEqual(
      failing,
      [],
      `Expected zero flex rules missing min-height: 0, but found: ${failing.map((r) => r.selector).join(', ')}`
    );
    assert.doesNotThrow(() => {
      assertFlexOverflowRulesHaveMinHeight(allRules);
    });
  });

  it('.app-content-body declares min-height: 0 and min-width: 0 in index.css', () => {
    const bodyRule = allRules.find((r) => r.selector === '.app-content-body');
    assert.ok(bodyRule, '.app-content-body rule must exist');
    assert.strictEqual(
      bodyRule.declarations.get('min-height'),
      '0',
      '.app-content-body must declare min-height: 0'
    );
    assert.strictEqual(
      bodyRule.declarations.get('min-width'),
      '0',
      '.app-content-body must declare min-width: 0'
    );
    assert.strictEqual(
      bodyRule.declarations.get('overflow-y'),
      'auto',
      '.app-content-body must declare overflow-y: auto'
    );
  });

  it('.trip-planner-card declares min-height: 0 in index.css', () => {
    const tripCardRule = allRules.find((r) => r.selector === '.trip-planner-card');
    assert.ok(tripCardRule, '.trip-planner-card rule must exist');
    assert.strictEqual(
      tripCardRule.declarations.get('min-height'),
      '0',
      '.trip-planner-card must declare min-height: 0'
    );
    assert.strictEqual(
      tripCardRule.declarations.get('overflow-y'),
      'auto',
      '.trip-planner-card must declare overflow-y: auto'
    );
  });

  it('.itinerary-results-container declares min-height: 0 in index.css (belt-and-braces)', () => {
    const resultsContainerRule = allRules.find((r) => r.selector === '.itinerary-results-container');
    assert.ok(resultsContainerRule, '.itinerary-results-container rule must exist');
    assert.strictEqual(
      resultsContainerRule.declarations.get('min-height'),
      '0',
      '.itinerary-results-container must declare min-height: 0'
    );
    assert.strictEqual(
      resultsContainerRule.declarations.get('overflow-y'),
      'auto',
      '.itinerary-results-container must declare overflow-y: auto'
    );
  });

  it('negative: fixture rule with flex: 1 and overflow-y: auto but missing min-height fails', () => {
    const fixtureCss = `
      .fixture-flex-item {
        flex: 1;
        overflow-y: auto;
      }
    `;
    const rules = parseCssRules(fixtureCss);
    const failing = findFlexOverflowRulesMissingMinHeight(rules);
    assert.strictEqual(failing.length, 1);
    assert.strictEqual(failing[0].selector, '.fixture-flex-item');
    assert.throws(
      () => assertFlexOverflowRulesHaveMinHeight(rules),
      /missing min-height: 0.*\.fixture-flex-item/
    );
  });

  it('negative: fixture rule with overflow-y: scroll and in-flow positioning missing min-height fails', () => {
    const fixtureCss = `
      .fixture-scroll-box {
        display: flex;
        overflow-y: scroll;
      }
    `;
    const rules = parseCssRules(fixtureCss);
    const failing = findFlexOverflowRulesMissingMinHeight(rules);
    assert.strictEqual(failing.length, 1);
    assert.strictEqual(failing[0].selector, '.fixture-scroll-box');
    assert.throws(
      () => assertFlexOverflowRulesHaveMinHeight(rules),
      /missing min-height: 0.*\.fixture-scroll-box/
    );
  });

  it('negative: regression fixture representing pre-fix .app-content-body fails', () => {
    const preFixAppBody = `
      .app-content-body {
        display: flex;
        flex-direction: column;
        flex: 1;
        overflow-y: auto;
        overflow-x: hidden;
      }
    `;
    const rules = parseCssRules(preFixAppBody);
    const failing = findFlexOverflowRulesMissingMinHeight(rules);
    assert.strictEqual(failing.length, 1);
    assert.strictEqual(failing[0].selector, '.app-content-body');
    assert.throws(
      () => assertFlexOverflowRulesHaveMinHeight(rules),
      /missing min-height: 0.*\.app-content-body/
    );
  });

  it('negative: fixture with min-height: auto fails (auto does not prevent flex expansion)', () => {
    const fixtureAutoMinHeight = `
      .fixture-auto-height {
        flex: 1;
        overflow-y: auto;
        min-height: auto;
      }
    `;
    const rules = parseCssRules(fixtureAutoMinHeight);
    const failing = findFlexOverflowRulesMissingMinHeight(rules);
    assert.strictEqual(failing.length, 1);
    assert.strictEqual(failing[0].selector, '.fixture-auto-height');
    assert.throws(
      () => assertFlexOverflowRulesHaveMinHeight(rules),
      /missing min-height: 0.*\.fixture-auto-height/
    );
  });

  it('out-of-flow elements (position: absolute) with overflow-y are excluded from flex-item min-height requirement', () => {
    const absoluteFixture = `
      .popup-menu {
        position: absolute;
        max-height: 200px;
        overflow-y: auto;
      }
    `;
    const rules = parseCssRules(absoluteFixture);
    const failing = findFlexOverflowRulesMissingMinHeight(rules);
    assert.deepStrictEqual(failing, []);
    assert.doesNotThrow(() => assertFlexOverflowRulesHaveMinHeight(rules));
  });
});
