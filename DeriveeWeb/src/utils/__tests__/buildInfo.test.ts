import { describe, it } from 'node:test';
import assert from 'node:assert';
import { formatBuildInfo, getBuildInfo, type BuildInfoInput } from '../buildInfo.ts';

describe('Build Info & Display Contract Tests', () => {
  describe('Positive Build Info Formatting', () => {
    it('formats short commit hash and timestamp into standard display string', () => {
      const formatted = formatBuildInfo({
        hash: '9885eb0',
        timestamp: '2026-10-02T15:00:00Z',
      });
      assert.strictEqual(formatted, '9885eb0 (2026-10-02T15:00:00Z)');
      assert.ok(formatted.includes('9885eb0'), 'Must contain short commit hash');
      assert.ok(formatted.includes('2026-10-02T15:00:00Z'), 'Must contain timestamp');
    });

    it('supports positional arguments overload formatBuildInfo(hash, timestamp)', () => {
      const formatted = formatBuildInfo('9885eb0', '2026-10-02T15:00:00Z');
      assert.strictEqual(formatted, '9885eb0 (2026-10-02T15:00:00Z)');
    });

    it('truncates 40-character full git SHA to 7-character short hash without leaking full SHA', () => {
      const fullSha = '9885eb0123456789abcdef0123456789abcdef01';
      const formatted = formatBuildInfo({
        hash: fullSha,
        timestamp: '2026-10-02T15:00:00Z',
      });

      assert.strictEqual(formatted, '9885eb0 (2026-10-02T15:00:00Z)');
      assert.ok(formatted.includes('9885eb0'), 'Must contain 7-char short hash');
      assert.ok(
        !formatted.includes(fullSha.slice(7)),
        'Must NOT leak the remainder of the 40-character SHA'
      );
    });

    it('handles hash only with missing timestamp cleanly', () => {
      const formatted = formatBuildInfo({ hash: '9885eb0' });
      assert.strictEqual(formatted, '9885eb0');
      assert.ok(formatted.includes('9885eb0'));
    });
  });

  describe('Negative Cases & Missing Environment (Graceful "unknown", never throws)', () => {
    it('returns graceful "unknown" when called without arguments and no build env is present', () => {
      const originalViteHash = process.env.VITE_COMMIT_HASH;
      const originalCfHash = process.env.CF_PAGES_COMMIT_SHA;
      const originalCommitHash = process.env.COMMIT_HASH;
      const originalViteTime = process.env.VITE_BUILD_TIME;
      const originalBuildTime = process.env.BUILD_TIME;

      try {
        delete process.env.VITE_COMMIT_HASH;
        delete process.env.CF_PAGES_COMMIT_SHA;
        delete process.env.COMMIT_HASH;
        delete process.env.VITE_BUILD_TIME;
        delete process.env.BUILD_TIME;

        const formatted = formatBuildInfo();
        assert.strictEqual(formatted, 'unknown');
      } finally {
        if (originalViteHash) process.env.VITE_COMMIT_HASH = originalViteHash;
        if (originalCfHash) process.env.CF_PAGES_COMMIT_SHA = originalCfHash;
        if (originalCommitHash) process.env.COMMIT_HASH = originalCommitHash;
        if (originalViteTime) process.env.VITE_BUILD_TIME = originalViteTime;
        if (originalBuildTime) process.env.BUILD_TIME = originalBuildTime;
      }
    });

    it('handles undefined, null, and empty inputs gracefully without throwing', () => {
      assert.strictEqual(formatBuildInfo(undefined), 'unknown');
      assert.strictEqual(formatBuildInfo(null), 'unknown');
      assert.strictEqual(formatBuildInfo({}), 'unknown');
      assert.strictEqual(formatBuildInfo('', ''), 'unknown');
      assert.strictEqual(formatBuildInfo('   ', '   '), 'unknown');
      assert.strictEqual(formatBuildInfo({ hash: '', timestamp: '' }), 'unknown');
      assert.strictEqual(formatBuildInfo({ hash: null, timestamp: null }), 'unknown');
      assert.strictEqual(formatBuildInfo('unknown', 'unknown'), 'unknown');
    });

    it('handles garbage or non-string inputs safely without throwing', () => {
      assert.strictEqual(formatBuildInfo(12345 as unknown as string, true as unknown as string), 'unknown');
      assert.strictEqual(formatBuildInfo({ hash: {} as unknown as string }), 'unknown');
      assert.strictEqual(formatBuildInfo([] as unknown as BuildInfoInput), 'unknown');
    });
  });

  describe('Internal ID & Path Leak Prevention (Rule 12 & Gate 1)', () => {
    it('does not leak internal file paths or .git directories into the UI copy', () => {
      const maliciousPaths = [
        '/home/hatch/workspace/derivee/.git/HEAD',
        'src/components/SystemInfoDrawer.tsx',
        'C:\\Users\\admin\\repo\\.git',
        'file:///workspace/derivee/dist/index.html',
      ];

      for (const p of maliciousPaths) {
        const formatted = formatBuildInfo({ hash: p, timestamp: '2026-10-02T15:00:00Z' });
        assert.ok(!formatted.includes('home'), 'Must not leak /home');
        assert.ok(!formatted.includes('.git'), 'Must not leak .git');
        assert.ok(!formatted.includes('SystemInfoDrawer'), 'Must not leak source file names');
        assert.ok(!formatted.includes('workspace'), 'Must not leak workspace path');
      }
    });

    it('does not leak database tokens, secrets, or exception strings', () => {
      const leakTokens = [
        'sqlite3_open_v2: database locked',
        'CF_PAGES_COMMIT_SHA=secret_value_12345',
        'TOKEN=Bearer_super_secret_jwt',
        '0xDEADBEEFCAFE',
      ];

      for (const token of leakTokens) {
        const formatted = formatBuildInfo({ hash: token, timestamp: '2026-10-02T15:00:00Z' });
        assert.ok(!formatted.toLowerCase().includes('sqlite3'));
        assert.ok(!formatted.toLowerCase().includes('secret'));
        assert.ok(!formatted.toLowerCase().includes('bearer'));
      }
    });
  });

  describe('Environment Variable Resolution & getBuildInfo', () => {
    it('resolves CF_PAGES_COMMIT_SHA when present in env', () => {
      const originalCfHash = process.env.CF_PAGES_COMMIT_SHA;
      try {
        process.env.CF_PAGES_COMMIT_SHA = 'abcdef1234567890abcdef1234567890abcdef12';
        const info = getBuildInfo();
        assert.strictEqual(info.hash, 'abcdef1');
      } finally {
        if (originalCfHash) {
          process.env.CF_PAGES_COMMIT_SHA = originalCfHash;
        } else {
          delete process.env.CF_PAGES_COMMIT_SHA;
        }
      }
    });

    it('resolves VITE_COMMIT_HASH when present in env', () => {
      const originalViteHash = process.env.VITE_COMMIT_HASH;
      const originalCfHash = process.env.CF_PAGES_COMMIT_SHA;
      try {
        delete process.env.CF_PAGES_COMMIT_SHA;
        process.env.VITE_COMMIT_HASH = '1234567';
        const info = getBuildInfo();
        assert.strictEqual(info.hash, '1234567');
      } finally {
        if (originalViteHash) {
          process.env.VITE_COMMIT_HASH = originalViteHash;
        } else {
          delete process.env.VITE_COMMIT_HASH;
        }
        if (originalCfHash) process.env.CF_PAGES_COMMIT_SHA = originalCfHash;
      }
    });
  });
});
