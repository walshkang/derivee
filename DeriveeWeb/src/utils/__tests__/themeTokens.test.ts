import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateStyleMin, latest } from '@maplibre/maplibre-gl-style-spec';
import {
  getStoredTheme,
  setStoredTheme,
  getSystemTheme,
  resolveTheme,
  THEME_STORAGE_KEY,
} from '../theme.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const INDEX_CSS_PATH = path.resolve(__dirname, '../../index.css');
const LIGHT_STYLE_PATH = path.resolve(__dirname, '../../../public/map-style-light.json');

describe('Theme State, Persistence & System-Preference Tests', () => {
  let mockStorage: Record<string, string> = {};

  beforeEach(() => {
    mockStorage = {};
    (globalThis as any).localStorage = {
      getItem: (key: string) => mockStorage[key] ?? null,
      setItem: (key: string, val: string) => {
        mockStorage[key] = String(val);
      },
      removeItem: (key: string) => {
        delete mockStorage[key];
      },
      clear: () => {
        mockStorage = {};
      },
    };
  });

  it('defaults to "system" when localStorage is empty', () => {
    const theme = getStoredTheme();
    assert.strictEqual(theme, 'system');
  });

  it('persists and retrieves explicit theme choices (light, dark, system)', () => {
    setStoredTheme('light');
    assert.strictEqual(getStoredTheme(), 'light');
    assert.strictEqual(mockStorage[THEME_STORAGE_KEY], 'light');

    setStoredTheme('dark');
    assert.strictEqual(getStoredTheme(), 'dark');
    assert.strictEqual(mockStorage[THEME_STORAGE_KEY], 'dark');

    setStoredTheme('system');
    assert.strictEqual(getStoredTheme(), 'system');
    assert.strictEqual(mockStorage[THEME_STORAGE_KEY], 'system');
  });

  it('negative case: invalid stored theme string falls back safely to "system"', () => {
    mockStorage[THEME_STORAGE_KEY] = 'sepia-vintage';
    assert.strictEqual(getStoredTheme(), 'system');

    mockStorage[THEME_STORAGE_KEY] = '';
    assert.strictEqual(getStoredTheme(), 'system');

    mockStorage[THEME_STORAGE_KEY] = 'DARK';
    assert.strictEqual(getStoredTheme(), 'system');
  });

  it('resolves system preference using prefers-color-scheme media query', () => {
    (globalThis as any).window = {
      matchMedia: (query: string) => ({
        matches: query.includes('dark'),
        media: query,
        addEventListener: () => {},
        removeEventListener: () => {},
      }),
    };

    assert.strictEqual(getSystemTheme(), 'dark');
    assert.strictEqual(resolveTheme('system'), 'dark');

    (globalThis as any).window = {
      matchMedia: (query: string) => ({
        matches: false,
        media: query,
        addEventListener: () => {},
        removeEventListener: () => {},
      }),
    };

    assert.strictEqual(getSystemTheme(), 'light');
    assert.strictEqual(resolveTheme('system'), 'light');
  });

  it('explicit light/dark override ignores system preference', () => {
    (globalThis as any).window = {
      matchMedia: (query: string) => ({
        matches: true, // System is dark
        media: query,
        addEventListener: () => {},
        removeEventListener: () => {},
      }),
    };

    assert.strictEqual(resolveTheme('light'), 'light');

    (globalThis as any).window = {
      matchMedia: (query: string) => ({
        matches: false, // System is light
        media: query,
        addEventListener: () => {},
        removeEventListener: () => {},
      }),
    };

    assert.strictEqual(resolveTheme('dark'), 'dark');
  });
});

describe('CSS Theme Tokens & Hardcoded Color Guard', () => {
  it('defines [data-theme="light"] in index.css with all required inverted tokens', () => {
    const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');

    // Check [data-theme="light"] block exists
    assert.match(
      css,
      /\[data-theme=["']?light["']?\]/,
      'index.css must define [data-theme="light"] block'
    );

    // Extract [data-theme="light"] block
    const match = css.match(/\[data-theme=["']?light["']?\]\s*\{([^}]+)\}/);
    assert.ok(match, 'Failed to extract [data-theme="light"] CSS block');
    const block = match[1];

    const expectedTokens: Record<string, string> = {
      '--bg-primary': '#FFFFFF',
      '--bg-secondary': '#F0F2F5',
      '--bg-card': 'rgba(255, 255, 255, 0.88)',
      '--bg-input': '#FFFFFF',
      '--text-primary': '#0a0f16',
      '--text-secondary': '#5b6b7f',
      '--text-muted': '#8a9aac',
      '--border-subtle': '#E2E8F0',
      '--border-highlight': '#CBD5E1',
    };

    for (const [token, expectedValue] of Object.entries(expectedTokens)) {
      const regex = new RegExp(`${token}\\s*:\\s*([^;]+);`, 'i');
      const tokenMatch = block.match(regex);
      assert.ok(tokenMatch, `Missing token ${token} in [data-theme="light"]`);

      const actual = tokenMatch[1].trim().replace(/\s+/g, ' ').toLowerCase();
      const expected = expectedValue.trim().replace(/\s+/g, ' ').toLowerCase();
      assert.strictEqual(
        actual,
        expected,
        `Token ${token} should be ${expectedValue}, got ${tokenMatch[1]}`
      );
    }
  });

  it('verifies accents remain unchanged across themes', () => {
    const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
    const rootBlockMatch = css.match(/:root\s*\{([^}]+)\}/);
    assert.ok(rootBlockMatch, 'Missing :root block');
    const rootBlock = rootBlockMatch[1];

    const accents = [
      '--accent-cyan',
      '--accent-sky',
      '--accent-amber',
      '--status-online',
      '--status-offline',
    ];

    for (const accent of accents) {
      assert.ok(rootBlock.includes(accent), `:root must define accent ${accent}`);
    }

    // [data-theme="light"] should NOT override or rebrand accents to different colors
    const lightMatch = css.match(/\[data-theme=["']?light["']?\]\s*\{([^}]+)\}/);
    if (lightMatch) {
      const lightBlock = lightMatch[1];
      for (const accent of accents) {
        assert.ok(
          !lightBlock.includes(accent),
          `Accents must remain unchanged; ${accent} should not be redefined in light theme`
        );
      }
    }
  });

  it('asserts no hardcoded dark hex colors (#070a0f-family) in component CSS outside token blocks', () => {
    const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');

    // Strip :root, [data-theme="..."], and @media rules that declare base tokens
    const componentCss = css
      .replace(/:root\s*\{[^}]*\}/g, '')
      .replace(/\[data-theme=[^\]]*\]\s*\{[^}]*\}/g, '');

    const forbiddenHexes = [
      /#070a0f\b/i,
      /#0d131d\b/i,
      /#121a27\b/i,
      /#1c283d\b/i,
      /#283a57\b/i,
      /#080c14\b/i,
      /#101c2e\b/i,
      /#090e18\b/i,
      /#0d1421\b/i,
      /#121a28\b/i,
      /#0d1a2d\b/i,
    ];

    const violations: { hex: string; line: number; text: string }[] = [];
    const lines = componentCss.split('\n');

    lines.forEach((line, idx) => {
      // Ignore comments
      const cleanLine = line.replace(/\/\*.*?\*\//g, '').trim();
      for (const regex of forbiddenHexes) {
        if (regex.test(cleanLine)) {
          violations.push({
            hex: regex.source,
            line: idx + 1,
            text: cleanLine,
          });
        }
      }
    });

    assert.strictEqual(
      violations.length,
      0,
      `Found ${violations.length} hardcoded dark hex values in component CSS: ${JSON.stringify(violations, null, 2)}`
    );
  });

  it('negative case: proves the hardcoded hex scanner detects forbidden colors when present', () => {
    const sampleDirtyCss = `
      .my-component {
        background: #070a0f;
        color: #fff;
      }
    `;
    const forbidden = /#070a0f\b/i;
    assert.ok(forbidden.test(sampleDirtyCss), 'Scanner must detect forbidden #070a0f');
  });

  it('ensures yellow N/Q/R/W line badges get dark text contrast in light theme', () => {
    const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');

    // Verify there is a rule ensuring dark text on light theme for yellow route badges
    assert.match(
      css,
      /\[data-theme=["']?light["']?\][^{]*\.route-pill-badge/,
      'Must have CSS rule for route-pill-badge contrast in light mode'
    );
  });
});

describe('Porcelain Basemap Style Specification Tests', () => {
  it('validates public/map-style-light.json exists and conforms to MapLibre style spec', () => {
    assert.ok(fs.existsSync(LIGHT_STYLE_PATH), 'public/map-style-light.json must exist');
    const styleContent = fs.readFileSync(LIGHT_STYLE_PATH, 'utf8');
    const style = JSON.parse(styleContent);

    // Sprite must be undefined (omitted) like dark style
    assert.strictEqual(
      style.sprite,
      undefined,
      'Light style must not define a relative sprite URL (omitted if unused)'
    );

    // Validate style spec
    const errors = validateStyleMin(style, latest);
    assert.strictEqual(
      errors.length,
      0,
      `map-style-light.json produced validation errors: ${JSON.stringify(errors)}`
    );

    // Background must be pure porcelain white (#FFFFFF)
    const bgLayer = style.layers.find((l: any) => l.id === 'background');
    assert.ok(bgLayer, 'Missing background layer in light map style');
    assert.strictEqual(
      bgLayer.paint['background-color'].toUpperCase(),
      '#FFFFFF',
      'Light basemap background must be pure porcelain white #FFFFFF'
    );
  });
});

describe('Theme Toggle Reachability & Relocation Contract', () => {
  const DRAWER_PATH = path.resolve(__dirname, '../../components/SystemInfoDrawer.tsx');
  const BOTTOM_SHEET_PATH = path.resolve(__dirname, '../../components/BottomSheet.tsx');
  const APP_PATH = path.resolve(__dirname, '../../App.tsx');

  it('verifies theme toggle controls are relocated to BottomSheet and removed from SystemInfoDrawer', () => {
    const drawerContent = fs.readFileSync(DRAWER_PATH, 'utf8');
    const bottomSheetContent = fs.readFileSync(BOTTOM_SHEET_PATH, 'utf8');

    // Controls must NOT exist in SystemInfoDrawer (where bottom sheet occludes them)
    assert.ok(!drawerContent.includes('theme-toggle-group'), 'SystemInfoDrawer must not contain theme-toggle-group');
    assert.ok(!drawerContent.includes('footer-theme-item'), 'SystemInfoDrawer must not contain footer-theme-item');
    assert.ok(!drawerContent.includes('onThemeChange'), 'SystemInfoDrawer must not receive onThemeChange prop');

    // Controls MUST exist in BottomSheet
    assert.ok(bottomSheetContent.includes('sheet-header-area'), 'BottomSheet must define sheet-header-area');
    assert.ok(bottomSheetContent.includes('sheet-display-row'), 'BottomSheet must define sheet-display-row');
    assert.ok(bottomSheetContent.includes('theme-toggle-group'), 'BottomSheet must contain theme-toggle-group');
    assert.ok(bottomSheetContent.includes('theme-toggle-system'), 'BottomSheet must contain theme-toggle-system');
    assert.ok(bottomSheetContent.includes('theme-toggle-light'), 'BottomSheet must contain theme-toggle-light');
    assert.ok(bottomSheetContent.includes('theme-toggle-dark'), 'BottomSheet must contain theme-toggle-dark');
  });

  it('negative case: proves footer drawer does not define or accept theme control props', () => {
    const drawerContent = fs.readFileSync(DRAWER_PATH, 'utf8');
    assert.strictEqual(
      drawerContent.includes('ThemeSetting'),
      false,
      'SystemInfoDrawer should have zero references to ThemeSetting type'
    );
    assert.strictEqual(
      drawerContent.includes('theme='),
      false,
      'SystemInfoDrawer should not have default theme prop'
    );
  });

  it('verifies BottomSheet theme toggle segmented control accessibility roles', () => {
    const bottomSheetContent = fs.readFileSync(BOTTOM_SHEET_PATH, 'utf8');
    assert.ok(bottomSheetContent.includes('role="radiogroup"'), 'Theme toggle group must specify role="radiogroup"');
    assert.ok(bottomSheetContent.includes('aria-label="Theme selection"'), 'Theme toggle group must specify aria-label="Theme selection"');
    assert.ok(bottomSheetContent.includes('role="radio"'), 'Theme toggle buttons must specify role="radio"');
    assert.ok(bottomSheetContent.includes('aria-checked='), 'Theme toggle buttons must specify dynamic aria-checked');
  });

  it('verifies App.tsx routes theme state to BottomSheet', () => {
    const appContent = fs.readFileSync(APP_PATH, 'utf8');
    assert.ok(
      /<BottomSheet[\s\S]*?theme=\{theme\}[\s\S]*?onThemeChange=\{setTheme\}/.test(appContent),
      'App.tsx must pass theme and onThemeChange to BottomSheet'
    );
    assert.ok(
      !/<SystemInfoDrawer[\s\S]*?theme=/.test(appContent),
      'App.tsx must not pass theme to SystemInfoDrawer'
    );
  });
});

describe('Device Visual Fixes: Wordmark, Spinner & Leg Detail Contracts', () => {
  const PACK_INSTALLER_PATH = path.resolve(__dirname, '../../components/PackInstaller.tsx');

  describe('Defect 2: Header Wordmark Theme Legibility Contract', () => {
    it('sets .app-title color to token var(--text-primary) for dark/light adaptation', () => {
      const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
      const appTitleMatch = css.match(/\.app-title\s*\{([^}]+)\}/);
      assert.ok(appTitleMatch, 'Must find .app-title CSS rule');

      const ruleBody = appTitleMatch[1];
      assert.match(
        ruleBody,
        /color:\s*var\(--text-primary\)/,
        '.app-title must use var(--text-primary) to adapt to active light/dark theme'
      );
    });

    it('negative case: rejects hardcoded #f1f5f9 on .app-title that washes out in light mode', () => {
      const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
      const appTitleMatch = css.match(/\.app-title\s*\{([^}]+)\}/);
      assert.ok(appTitleMatch);
      const ruleBody = appTitleMatch[1];
      assert.doesNotMatch(
        ruleBody,
        /#f1f5f9/i,
        '.app-title must NOT hardcode #f1f5f9 which renders invisible on white header'
      );
    });
  });

  describe('Defect 3: Pack Installer Concentric Spinner Geometry Contract', () => {
    it('renders concentric SVG contour tracking icon square container bounds', () => {
      const tsx = fs.readFileSync(PACK_INSTALLER_PATH, 'utf8');
      assert.ok(
        tsx.includes('<svg class="spinner-ring" viewBox="0 0 54 54"'),
        'Installing beacon must use SVG contour with viewBox matching container'
      );
      assert.ok(
        tsx.includes('class="spinner-arc"'),
        'Must define spinner-arc element'
      );
      assert.ok(
        tsx.includes('pathLength="100"'),
        'Must specify pathLength="100" for normalized stroke perimeter tracking'
      );
      assert.ok(
        tsx.includes('rx="13"'),
        'Must specify corner radius rx="13" matching container border-radius'
      );
    });

    it('animates stroke-dashoffset along perimeter instead of rotating the square div', () => {
      const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
      const spinnerRingMatch = css.match(/\.spinner-ring\s*\{([^}]+)\}/);
      assert.ok(spinnerRingMatch, 'Must find .spinner-ring rule');
      assert.doesNotMatch(
        spinnerRingMatch[1],
        /animation:\s*spin/i,
        '.spinner-ring must NOT rotate the container via animation: spin'
      );

      assert.match(
        css,
        /\.spinner-arc\s*\{[^}]*animation:\s*spinner-contour-spin/i,
        '.spinner-arc must animate stroke-dashoffset around the contour'
      );
      assert.match(
        css,
        /@keyframes\s+spinner-contour-spin\s*\{[^}]*stroke-dashoffset/i,
        'Must define keyframes for stroke-dashoffset contour traversal'
      );
    });

    it('negative case: rejects transform: rotate(360deg) on non-circular spinner container', () => {
      const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
      const spinnerRingMatch = css.match(/\.spinner-ring\s*\{([^}]+)\}/);
      assert.ok(spinnerRingMatch);
      assert.doesNotMatch(
        spinnerRingMatch[1],
        /transform:\s*rotate/i,
        'Static container must not have transform: rotate'
      );
    });
  });

  describe('Defect 4: Leg Detail Light Mode Contrast & Visibility Contract', () => {
    it('sets .leg-stop-name color to var(--text-primary) for dark/light adaptation', () => {
      const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
      const stopNameMatch = css.match(/\.leg-stop-name\s*\{([^}]+)\}/);
      assert.ok(stopNameMatch, 'Must find .leg-stop-name rule');
      assert.match(
        stopNameMatch[1],
        /color:\s*var\(--text-primary\)/,
        '.leg-stop-name must use var(--text-primary)'
      );
    });

    it('provides high-contrast token color for .leg-connector-line in light theme', () => {
      const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
      assert.match(
        css,
        /\[data-theme=["']?light["']?\]\s*\.leg-connector-line\s*\{[^}]*background-color:\s*var\(--text-secondary\)/,
        'Light theme must style .leg-connector-line with var(--text-secondary) for WCAG AA visibility'
      );
    });

    it('styles leg stop times and metadata with readable secondary token in light mode', () => {
      const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
      assert.match(
        css,
        /\[data-theme=["']?light["']?\]\s*\.leg-stop-time\s*\{[^}]*color:\s*var\(--text-secondary\)/,
        'Light theme must style .leg-stop-time with var(--text-secondary)'
      );
      assert.match(
        css,
        /\[data-theme=["']?light["']?\]\s*\.leg-card-header\s*\{[^}]*color:\s*var\(--text-secondary\)/,
        'Light theme must style .leg-card-header with var(--text-secondary)'
      );
    });

    it('negative case: rejects hardcoded white #f1f5f9 on .leg-stop-name', () => {
      const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
      const stopNameMatch = css.match(/\.leg-stop-name\s*\{([^}]+)\}/);
      assert.ok(stopNameMatch);
      assert.doesNotMatch(
        stopNameMatch[1],
        /#f1f5f9/i,
        '.leg-stop-name must NOT hardcode #f1f5f9'
      );
    });

    it('negative case: rejects faint --border-highlight for .leg-connector-line in light mode', () => {
      const css = fs.readFileSync(INDEX_CSS_PATH, 'utf8');
      const lightConnectorMatch = css.match(/\[data-theme=["']?light["']?\]\s*\.leg-connector-line\s*\{([^}]+)\}/);
      assert.ok(lightConnectorMatch, 'Must find light theme .leg-connector-line rule');
      assert.doesNotMatch(
        lightConnectorMatch[1],
        /var\(--border-highlight\)/,
        'Light connector line must not use faint --border-highlight which is invisible on card background'
      );
    });
  });
});


