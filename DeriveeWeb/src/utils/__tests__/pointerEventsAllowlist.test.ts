import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SRC_DIR = path.resolve(__dirname, '../..');
const INDEX_CSS_PATH = path.join(SRC_DIR, 'index.css');
const COMPONENTS_DIR = path.join(SRC_DIR, 'components');

/**
 * Parses the pointer-events: auto allowlist selectors directly from index.css.
 * Specifically targets the rule following .app-content-body that re-enables
 * pointer events for interactive overlay cards/sections.
 */
export function parseAllowlistSelectors(cssContent: string): string[] {
  const cleanCss = cssContent.replace(/\/\*[\s\S]*?\*\//g, '');
  const match = cleanCss.match(
    /\.app-content-body\s*\{[^}]*\}\s*([^\{]+)\{\s*pointer-events:\s*auto;?\s*\}/
  );
  if (!match) {
    throw new Error('Could not find .app-content-body pointer-events allowlist rule in index.css');
  }

  return match[1]
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

/**
 * Scans all TSX files in the components directory and extracts every CSS class name
 * defined in JSX class="..." or className="..." attributes.
 */
export function collectComponentClasses(componentsDir: string): Set<string> {
  const classes = new Set<string>();
  const files = fs.readdirSync(componentsDir).filter((f) => f.endsWith('.tsx'));

  for (const file of files) {
    const fullPath = path.join(componentsDir, file);
    const content = fs.readFileSync(fullPath, 'utf8');

    // Match static double-quoted: class="..." or className="..."
    for (const match of content.matchAll(/\b(?:class|className)\s*=\s*"([^"]+)"/g)) {
      for (const cls of match[1].split(/\s+/)) {
        if (cls.trim()) classes.add(cls.trim());
      }
    }

    // Match static single-quoted: class='...' or className='...'
    for (const match of content.matchAll(/\b(?:class|className)\s*=\s*'([^']+)'/g)) {
      for (const cls of match[1].split(/\s+/)) {
        if (cls.trim()) classes.add(cls.trim());
      }
    }

    // Match template literals: class={`...`} or className={`...`}
    for (const match of content.matchAll(/\b(?:class|className)\s*=\s*\{`([^`]+)`\}/g)) {
      const templateLiteral = match[1];
      const staticParts = templateLiteral.replace(/\$\{[^}]*\}/g, ' ');
      for (const cls of staticParts.split(/\s+/)) {
        if (cls.trim()) classes.add(cls.trim());
      }
      for (const expr of templateLiteral.matchAll(/\$\{([^}]+)\}/g)) {
        for (const str of expr[1].matchAll(/['"]([^'"]+)['"]/g)) {
          for (const cls of str[1].split(/\s+/)) {
            if (cls.trim()) classes.add(cls.trim());
          }
        }
      }
    }
  }

  return classes;
}

/**
 * Validates a list of CSS selectors against known component classes.
 * Returns unmatched (dead) selectors.
 */
export function findDeadSelectors(selectors: string[], componentClasses: Set<string>): string[] {
  const dead: string[] = [];
  for (const selector of selectors) {
    const className = selector.startsWith('.') ? selector.slice(1) : selector;
    if (!componentClasses.has(className)) {
      dead.push(selector);
    }
  }
  return dead;
}

export function assertAllowlistValid(selectors: string[], componentClasses: Set<string>): void {
  const dead = findDeadSelectors(selectors, componentClasses);
  if (dead.length > 0) {
    throw new Error(
      `Allowlist contains dead selectors that match no component in DeriveeWeb/src/components/*.tsx: ${dead.join(', ')}`
    );
  }
}

describe('Pointer-events Allowlist Dead-Selector Guard', () => {
  const cssContent = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
  const componentClasses = collectComponentClasses(COMPONENTS_DIR);

  it('parses allowlist selectors successfully from src/index.css', () => {
    const selectors = parseAllowlistSelectors(cssContent);
    assert.ok(selectors.length > 0, 'Allowlist should contain at least one selector');
    assert.ok(
      selectors.includes('.trip-planner-card'),
      'Allowlist must include .trip-planner-card for TripPlanner pointer interaction'
    );
    assert.ok(
      selectors.includes('.search-section'),
      'Allowlist must include .search-section for SearchBar pointer interaction'
    );
    assert.ok(
      selectors.includes('.pack-installer-card'),
      'Allowlist must include .pack-installer-card for PackInstaller pointer interaction'
    );
    assert.ok(
      selectors.includes('.pack-installed-panel'),
      'Allowlist must include .pack-installed-panel for PackInstaller banner pointer interaction'
    );
  });

  it('asserts EVERY allowlist selector in index.css matches at least one real component class', () => {
    const selectors = parseAllowlistSelectors(cssContent);
    const dead = findDeadSelectors(selectors, componentClasses);
    assert.deepStrictEqual(
      dead,
      [],
      `Expected zero dead selectors in index.css allowlist, but found: ${dead.join(', ')}`
    );
    assert.doesNotThrow(() => {
      assertAllowlistValid(selectors, componentClasses);
    });
  });

  it('negative case: assert the test fails when given a bogus selector (.itinerary-planner-card)', () => {
    const bogusSelectors = ['.itinerary-planner-card'];
    const dead = findDeadSelectors(bogusSelectors, componentClasses);
    assert.deepStrictEqual(dead, ['.itinerary-planner-card']);
    assert.throws(
      () => {
        assertAllowlistValid(bogusSelectors, componentClasses);
      },
      {
        name: 'Error',
        message: /Allowlist contains dead selectors.*\.itinerary-planner-card/,
      }
    );
  });

  it('negative case: assert the test fails on other non-existent selectors (.itinerary-container, .pack-installer-container)', () => {
    const nonExistent = ['.itinerary-container', '.pack-installer-container'];
    const dead = findDeadSelectors(nonExistent, componentClasses);
    assert.deepStrictEqual(dead, nonExistent);
    assert.throws(
      () => {
        assertAllowlistValid(nonExistent, componentClasses);
      },
      {
        name: 'Error',
        message: /Allowlist contains dead selectors.*\.itinerary-container.*\.pack-installer-container/,
      }
    );
  });

  it('regression: proves this test would have caught commit b30bc7e regression', () => {
    const b30bc7eSelectors = [
      '.search-section',
      '.pack-installer-container',
      '.pack-installer-card',
      '.itinerary-planner-card',
      '.itinerary-container',
    ];

    const dead = findDeadSelectors(b30bc7eSelectors, componentClasses);
    assert.deepStrictEqual(dead, [
      '.pack-installer-container',
      '.itinerary-planner-card',
      '.itinerary-container',
    ]);

    assert.throws(
      () => {
        assertAllowlistValid(b30bc7eSelectors, componentClasses);
      },
      {
        name: 'Error',
        message: /\.pack-installer-container, \.itinerary-planner-card, \.itinerary-container/,
      }
    );
  });
});
