import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateStyleMin, latest } from '@maplibre/maplibre-gl-style-spec';
import { isFatalMapError } from '../mapErrorClassification.ts';

// Setup minimal browser-like globals required by MapLibre's Style runtime
(globalThis as any).self = globalThis;
globalThis.window = globalThis as any;
if (!globalThis.location) {
  globalThis.location = new URL('http://localhost') as any;
}
if (!globalThis.ImageData) {
  globalThis.ImageData = class ImageData {} as any;
}
if (!globalThis.Worker) {
  globalThis.Worker = class Worker {
    postMessage() {}
    addEventListener() {}
    removeEventListener() {}
    terminate() {}
  } as any;
}
// MapLibre's Actor ThrottledInvoker creates a MessageChannel whose ports keep Node.js event loop alive unless closed/mocked
globalThis.MessageChannel = class MockMessageChannel {
  port1: any;
  port2: any;
  constructor() {
    this.port2 = { onmessage: null };
    this.port1 = {
      postMessage: () => {
        queueMicrotask(() => {
          if (this.port2.onmessage) this.port2.onmessage();
        });
      }
    };
  }
} as any;


import { Style } from 'maplibre-gl';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const SHIPPED_STYLE_PATH = path.resolve(__dirname, '../../../public/map-style-dark.json');

function createMockMapInstance() {
  return {
    _getMapId: () => 1,
    _requestManager: {
      transformRequest: (url: string) => ({ url }),
    },
    getPixelRatio: () => 1,
    setTerrain: () => {},
    getTerrain: () => null,
    migrateProjection: () => {},
    painter: { glyphManager: {} },
  } as any;
}

function runRealMapLibreSpriteValidation(spriteValue: any): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const style = new Style(createMockMapInstance());
    style.on('error', () => {});
    style.loadEmpty();
    style.setSprite(spriteValue, {}, (err) => {
      if (err) {
        reject(err);
      } else {
        resolve();
      }
    });
  });
}

describe('Map Style Specification & Sprite URL Validation Tests', () => {
  it('validates the ACTUAL shipped map-style-dark.json against MapLibre style validation (Red->Green)', async () => {
    const styleContent = fs.readFileSync(SHIPPED_STYLE_PATH, 'utf8');
    const style = JSON.parse(styleContent);

    // The shipped style must not have an un-prefixed relative sprite key that crashes MapLibre
    assert.strictEqual(
      style.sprite,
      undefined,
      'Shipped style must not define a relative sprite URL (must be omitted if unused)'
    );

    // Run the actual shipped sprite through real MapLibre Style.setSprite
    // This MUST pass cleanly without throwing "Invalid sprite URL, must be absolute"
    await runRealMapLibreSpriteValidation(style.sprite);

    // Validate overall style against @maplibre/maplibre-gl-style-spec
    const errors = validateStyleMin(style, latest);
    assert.strictEqual(errors.length, 0, `Shipped style must produce 0 style-spec validation errors: ${JSON.stringify(errors)}`);
  });

  it('end-to-end Style load: pre-fix style triggers fatal sprite error event, while shipped style loads without sprite error', async () => {
    const shippedStyle = JSON.parse(fs.readFileSync(SHIPPED_STYLE_PATH, 'utf8'));
    const preFixStyle = { ...shippedStyle, sprite: '/sprites/dark' };

    // 1. Pre-fix style load: MapLibre fires fatal error event for relative sprite
    const preFixStyleInstance = new Style(createMockMapInstance());
    let preFixError: Error | null = null;
    preFixStyleInstance.on('error', (e: any) => {
      const err = e.error || e;
      if (err.message?.includes('sprite')) {
        preFixError = err;
      }
    });
    preFixStyleInstance._load(preFixStyle, { validate: false });

    // Allow microtasks/promises to settle
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.ok(preFixError, 'Pre-fix style must fire an error event for sprite');
    assert.ok(
      (preFixError as any).message.includes('Invalid sprite URL "/sprites/dark", must be absolute'),
      `Error must match MapLibre ground truth: ${(preFixError as any).message}`
    );
    assert.strictEqual(isFatalMapError(preFixError), true, 'Sprite error must be classified as fatal');

    // 2. Shipped style load: MapLibre loads without any sprite error
    const shippedStyleInstance = new Style(createMockMapInstance());
    let shippedSpriteError: Error | null = null;
    shippedStyleInstance.on('error', (e: any) => {
      const err = e.error || e;
      if (err.message?.includes('sprite')) {
        shippedSpriteError = err;
      }
    });
    shippedStyleInstance._load(shippedStyle, { validate: false });

    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.strictEqual(shippedSpriteError, null, 'Shipped style must not trigger any sprite error');
  });

  it('negative case: pre-fix relative sprite URL is rejected by real MapLibre and classified as fatal', async () => {
    const preFixSprite = '/sprites/dark';

    let thrownError: Error | null = null;
    try {
      await runRealMapLibreSpriteValidation(preFixSprite);
    } catch (err: any) {
      thrownError = err;
    }

    assert.ok(thrownError, 'MapLibre must reject relative sprite URL');
    assert.ok(
      thrownError.message.includes('Invalid sprite URL "/sprites/dark", must be absolute'),
      `Error message must match MapLibre ground truth verbatim: got "${thrownError.message}"`
    );
    assert.ok(
      thrownError.message.includes('TransformStyleFunction'),
      'Error message must reference TransformStyleFunction suggestion'
    );

    // Assert the error is classified as FATAL by our error classification contract
    assert.strictEqual(
      isFatalMapError(thrownError),
      true,
      'Relative sprite URL failure must be classified as a fatal map error'
    );
  });

  it('negative case: malformed or broken relative sprite URL is rejected by MapLibre and classified as fatal', async () => {
    const malformedSprite = 'relative/path/no/scheme';

    let thrownError: Error | null = null;
    try {
      await runRealMapLibreSpriteValidation(malformedSprite);
    } catch (err: any) {
      thrownError = err;
    }

    assert.ok(thrownError, 'MapLibre must reject malformed relative sprite URL');
    assert.ok(
      thrownError.message.includes('must be absolute'),
      'Error message must complain that sprite URL must be absolute'
    );
    assert.strictEqual(isFatalMapError(thrownError), true);
  });

  it('verifies shipped glyphs URL format and MapLibre glyphManager acceptance', () => {
    const styleContent = fs.readFileSync(SHIPPED_STYLE_PATH, 'utf8');
    const style = JSON.parse(styleContent);

    assert.ok(style.glyphs, 'Shipped style must define glyphs');
    assert.ok(
      style.glyphs.includes('{fontstack}'),
      'Glyphs URL must include {fontstack} token per style spec'
    );
    assert.ok(
      style.glyphs.includes('{range}'),
      'Glyphs URL must include {range} token per style spec'
    );

    // Style.setGlyphs must accept the relative glyphs URL without throwing
    const styleInstance = new Style(createMockMapInstance());
    styleInstance.loadEmpty();
    assert.doesNotThrow(() => {
      styleInstance.setGlyphs(style.glyphs);
    }, 'MapLibre Style must accept glyphs template without throwing');
  });

  it('negative case: glyphs URL missing required tokens is flagged by style-spec validator', () => {
    const brokenGlyphsStyle = {
      version: 8 as const,
      glyphs: '/fonts/invalid-template.pbf',
      sources: {},
      layers: [],
    };

    const errors = validateStyleMin(brokenGlyphsStyle, latest);
    assert.ok(errors.length > 0, 'style-spec validator must flag missing tokens in glyphs URL');
    const tokenError = errors.find((e) => e.message.includes('{fontstack}') || e.message.includes('{range}'));
    assert.ok(tokenError, 'style-spec validator must explicitly mention missing {fontstack} or {range} token');
  });

  it('confirms zero style layers reference icon-image or sprite patterns (no visual regression)', () => {
    const styleContent = fs.readFileSync(SHIPPED_STYLE_PATH, 'utf8');
    const style = JSON.parse(styleContent);

    const layersWithIcons: string[] = [];
    const layersWithPatterns: string[] = [];

    for (const layer of style.layers || []) {
      if (layer.layout?.['icon-image']) {
        layersWithIcons.push(layer.id);
      }
      if (layer.paint?.['fill-pattern'] || layer.paint?.['line-pattern'] || layer.paint?.['background-pattern']) {
        layersWithPatterns.push(layer.id);
      }
    }

    assert.strictEqual(
      layersWithIcons.length,
      0,
      `No style layer may reference icon-image (found: ${layersWithIcons.join(', ')})`
    );
    assert.strictEqual(
      layersWithPatterns.length,
      0,
      `No style layer may reference sprite patterns (found: ${layersWithPatterns.join(', ')})`
    );
  });
});
