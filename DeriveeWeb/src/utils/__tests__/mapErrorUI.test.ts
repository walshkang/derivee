import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('Map Error UI Tests', () => {
  it('asserts the error UI exposes the underlying message', () => {
    const basemapViewPath = path.resolve(__dirname, '../../components/BasemapView.tsx');
    const content = fs.readFileSync(basemapViewPath, 'utf8');

    // The component must render snapshot.errorDetails to surface the real underlying error
    assert.ok(
      content.includes('{snapshot.errorDetails}'),
      'BasemapView.tsx must surface snapshot.errorDetails in the UI'
    );
  });
});
