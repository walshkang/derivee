import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseCssRules } from './scrollChain.test.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_DIR = path.resolve(__dirname, '../../..');
const INDEX_HTML_PATH = path.join(ROOT_DIR, 'index.html');
const INDEX_CSS_PATH = path.join(ROOT_DIR, 'src/index.css');
const BOTTOM_SHEET_PATH = path.join(ROOT_DIR, 'src/components/BottomSheet.tsx');

describe('Standalone-Mode UI Configuration & Hardening', () => {
  const htmlContent = fs.readFileSync(INDEX_HTML_PATH, 'utf8');
  const cssContent = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
  const cssRules = parseCssRules(cssContent);
  const bottomSheetContent = fs.readFileSync(BOTTOM_SHEET_PATH, 'utf8');

  describe('index.html Meta & Apple Tags Contract', () => {
    it('declares viewport-fit=cover in viewport meta tag', () => {
      const viewportMatch = htmlContent.match(/<meta\s+name=["']viewport["']\s+content=["']([^"']+)["']/i);
      assert.ok(viewportMatch, 'index.html must have a viewport meta tag');
      const content = viewportMatch[1];
      assert.ok(
        content.includes('viewport-fit=cover'),
        `viewport content must include "viewport-fit=cover", found: "${content}"`
      );
    });

    it('declares apple-mobile-web-app-capable=yes', () => {
      assert.match(
        htmlContent,
        /<meta\s+name=["']apple-mobile-web-app-capable["']\s+content=["']yes["']/i,
        'Must enable apple-mobile-web-app-capable for standalone launch'
      );
    });

    it('declares apple-mobile-web-app-status-bar-style=black-translucent', () => {
      assert.match(
        htmlContent,
        /<meta\s+name=["']apple-mobile-web-app-status-bar-style["']\s+content=["']black-translucent["']/i,
        'Must specify black-translucent status bar style for edge-to-edge rendering'
      );
    });

    it('declares format-detection=telephone=no to suppress accidental iOS dialer popups', () => {
      assert.match(
        htmlContent,
        /<meta\s+name=["']format-detection["']\s+content=["']telephone=no["']/i,
        'Must suppress iOS telephone format detection'
      );
    });

    it('declares apple-touch-icon links for home screen icon generation', () => {
      assert.match(
        htmlContent,
        /<link\s+rel=["']apple-touch-icon["']/i,
        'Must have apple-touch-icon link element'
      );
    });

    it('negative case: ensures missing viewport-fit=cover is detectable', () => {
      const brokenHtml = '<meta name="viewport" content="width=device-width, initial-scale=1.0" />';
      assert.strictEqual(brokenHtml.includes('viewport-fit=cover'), false);
    });
  });

  describe('Safe-Area Insets & CSS Layout Boundaries', () => {
    it('.app-header declares safe-area-inset-top padding', () => {
      const headerRule = cssRules.find((r) => r.selector === '.app-header');
      assert.ok(headerRule, '.app-header rule must exist');
      const paddingTop = headerRule.declarations.get('padding-top');
      assert.ok(paddingTop, 'padding-top must be declared');
      assert.ok(
        paddingTop.includes('safe-area-inset-top'),
        `Header padding-top must use safe-area-inset-top, got: ${paddingTop}`
      );
    });

    it('.system-footer-drawer declares safe-area-inset-bottom padding', () => {
      const footerRule = cssRules.find((r) => r.selector === '.system-footer-drawer');
      assert.ok(footerRule, '.system-footer-drawer rule must exist');
      const paddingBottom = footerRule.declarations.get('padding-bottom');
      assert.ok(paddingBottom, 'padding-bottom must be declared');
      assert.ok(
        paddingBottom.includes('safe-area-inset-bottom'),
        `Footer padding-bottom must use safe-area-inset-bottom, got: ${paddingBottom}`
      );
    });

    it('.bottom-sheet-content declares safe-area-inset-bottom padding', () => {
      const sheetRule = cssRules.find((r) => r.selector === '.bottom-sheet-content');
      assert.ok(sheetRule, '.bottom-sheet-content rule must exist');
      const padding = sheetRule.declarations.get('padding');
      assert.ok(padding, 'padding must be declared on .bottom-sheet-content');
      assert.ok(
        padding.includes('safe-area-inset-bottom'),
        `.bottom-sheet-content padding must include safe-area-inset-bottom, got: ${padding}`
      );
    });

    it('negative case: fixture missing safe-area-inset-bottom is rejected', () => {
      const fixtureCss = '.faulty-sheet { padding: 0 16px 16px; }';
      const parsed = parseCssRules(fixtureCss);
      const decl = parsed[0].declarations.get('padding');
      assert.strictEqual(decl?.includes('safe-area-inset-bottom'), false);
    });
  });

  describe('100dvh Dynamic Viewport & Overscroll Suppression', () => {
    it('#app declares height: 100dvh', () => {
      const appRule = cssRules.find((r) => r.selector === '#app');
      assert.ok(appRule, '#app rule must exist');
      assert.ok(
        appRule.raw.includes('100dvh'),
        '#app must declare 100dvh'
      );
    });

    it('.app-layout declares height: 100dvh and overscroll-behavior: none', () => {
      const layoutRule = cssRules.find((r) => r.selector === '.app-layout');
      assert.ok(layoutRule, '.app-layout rule must exist');
      assert.ok(layoutRule.raw.includes('100dvh'), '.app-layout must declare 100dvh');
      assert.strictEqual(
        layoutRule.declarations.get('overscroll-behavior'),
        'none',
        '.app-layout must declare overscroll-behavior: none'
      );
    });

    it('html, body declares overscroll-behavior: none and overscroll-behavior-y: none', () => {
      const htmlBodyRule = cssRules.find((r) => r.selector === 'html, body');
      assert.ok(htmlBodyRule, 'html, body rule must exist');
      assert.strictEqual(
        htmlBodyRule.declarations.get('overscroll-behavior'),
        'none',
        'html, body must declare overscroll-behavior: none to prevent rubber-band bounce'
      );
      assert.strictEqual(
        htmlBodyRule.declarations.get('overscroll-behavior-y'),
        'none',
        'html, body must declare overscroll-behavior-y: none'
      );
    });

    it('.trip-planner-card declares 100dvh max-height', () => {
      const cardRule = cssRules.find((r) => r.selector === '.trip-planner-card');
      assert.ok(cardRule, '.trip-planner-card rule must exist');
      assert.ok(
        cardRule.raw.includes('100dvh'),
        '.trip-planner-card must declare 100dvh max-height'
      );
    });

    it('BottomSheet component uses dvh units instead of raw vh for dynamic heights', () => {
      assert.ok(
        bottomSheetContent.includes('dvh'),
        'BottomSheet.tsx must reference dvh units'
      );
      // Ensure no raw "vh" string literals remain in height styles
      const hasRawVhStyle = /\$\{.*\}vh['"`]/.test(bottomSheetContent);
      assert.strictEqual(
        hasRawVhStyle,
        false,
        'BottomSheet.tsx should not use raw ${...}vh styles for sheet heights'
      );
    });

    it('negative case: fixture with raw vh style is detected', () => {
      const fixtureCode = 'sheet.style.height = `${percent}vh`;';
      const isRawVh = /\$\{.*\}vh/.test(fixtureCode);
      assert.strictEqual(isRawVh, true);
    });
  });

  describe('Tap Highlight & Callout Suppression', () => {
    it('declares -webkit-tap-highlight-color: transparent across all elements', () => {
      const universalRule = cssRules.find((r) => r.selector === '*, *::before, *::after');
      assert.ok(universalRule, 'Universal selector rule must exist');
      assert.strictEqual(
        universalRule.declarations.get('-webkit-tap-highlight-color'),
        'transparent'
      );
    });

    it('suppresses -webkit-touch-callout on interactive controls and root', () => {
      const htmlBodyRule = cssRules.find((r) => r.selector === 'html, body');
      assert.ok(htmlBodyRule);
      assert.strictEqual(
        htmlBodyRule.declarations.get('-webkit-touch-callout'),
        'none',
        'html, body must declare -webkit-touch-callout: none'
      );

      const controlRule = cssRules.find((r) =>
        r.selector.includes('button') && r.selector.includes('.map-viewport-canvas')
      );
      assert.ok(controlRule, 'Controls touch-callout rule must exist');
      assert.strictEqual(
        controlRule.declarations.get('-webkit-touch-callout'),
        'none'
      );
    });

    it('preserves user-select: text on text input fields', () => {
      const inputRule = cssRules.find((r) => r.selector.includes('input') && r.selector.includes('textarea'));
      assert.ok(inputRule, 'Input user-select rule must exist');
      assert.strictEqual(
        inputRule.declarations.get('user-select'),
        'text',
        'Text inputs must preserve user-select: text'
      );
      assert.strictEqual(
        inputRule.declarations.get('-webkit-user-select'),
        'text',
        'Text inputs must preserve -webkit-user-select: text'
      );
    });

    it('negative case: fixture missing user-select: text on inputs is caught', () => {
      const badInputCss = 'input { font-size: 14px; }';
      const parsed = parseCssRules(badInputCss);
      assert.strictEqual(parsed[0].declarations.get('user-select') ?? null, null);
    });
  });
});
