import { describe, it } from 'node:test';
import assert from 'node:assert';
import { runBasemapInstall } from '../basemapInstallerCore.ts';
import type { BasemapWorkerToMainMessage } from '../../types/basemap.ts';

function createValidPMTilesHeader(): Uint8Array {
  const buf = new Uint8Array(127);
  // Magic bytes "PMTiles"
  buf.set([0x50, 0x4D, 0x54, 0x69, 0x6C, 0x65, 0x73], 0);
  buf[7] = 3; // Spec version 3
  const view = new DataView(buf.buffer);
  view.setUint32(56, 127, true); // tileDataOffset
  view.setUint32(64, 50, true);  // tileDataLength
  view.setUint32(80, 5, true);   // numTileEntries
  buf[99] = 1;                   // tileType MVT
  buf[100] = 0;                  // minZoom
  buf[101] = 14;                 // maxZoom
  return buf;
}

function createMockResponse(totalBytes: number, chunks: Uint8Array[], hangAfterChunks: boolean = false) {
  let chunkIdx = 0;
  const mockReader = {
    read: async () => {
      if (chunkIdx < chunks.length) {
        const val = chunks[chunkIdx++];
        return { done: false, value: val };
      }
      if (hangAfterChunks) {
        return new Promise<{ done: boolean; value: undefined }>(() => {});
      }
      return { done: true, value: undefined };
    },
  };
  return {
    ok: true,
    headers: {
      get: (h: string) => (h.toLowerCase() === 'content-length' ? String(totalBytes) : null),
    },
    body: {
      getReader: () => mockReader,
    },
  } as unknown as Response;
}

function createMockFs(options?: {
  closeNeverSettles?: boolean;
  getFileNeverSettles?: boolean;
  arrayBufferNeverSettles?: boolean;
}) {
  const validHeader = createValidPMTilesHeader();
  const mockFile = {
    size: 500,
    slice: () => ({
      arrayBuffer: async () => {
        if (options?.arrayBufferNeverSettles) {
          return new Promise<ArrayBuffer>(() => {});
        }
        return validHeader.buffer.slice(0, 127);
      },
    }),
  };

  const mockWritable = {
    write: async () => {},
    close: async () => {
      if (options?.closeNeverSettles) {
        return new Promise<void>(() => {});
      }
    },
  };

  const mockFileHandle = {
    createWritable: async () => mockWritable,
    getFile: async () => {
      if (options?.getFileNeverSettles) {
        return new Promise<File>(() => {});
      }
      return mockFile as unknown as File;
    },
  };

  const mockCityDir = {
    getFileHandle: async () => mockFileHandle as unknown as FileSystemFileHandle,
  };

  return {
    getCityDirectoryHandle: async () => mockCityDir as unknown as FileSystemDirectoryHandle,
  };
}

describe('Basemap Worker Stall Watchdog & Boundary Timeouts', () => {
  it('Candidate 1: reader.read() never returns done after 100% bytes -> times out with stage DOWNLOAD_COMPLETE', async () => {
    const messages: BasemapWorkerToMainMessage[] = [];
    const chunk = new Uint8Array(100);
    const mockFs = createMockFs();

    await runBasemapInstall('nyc', '/api/basemap', {
      postMessage: (msg) => messages.push(msg),
      fetch: async () => createMockResponse(100, [chunk], true /* hang after receiving 100% bytes */),
      getCityDirectoryHandle: mockFs.getCityDirectoryHandle,
      deletePartialFile: async () => {},
      readEofTimeoutMs: 30,
    });

    const errorMsg = messages.find((m) => m.type === 'ERROR');
    assert.ok(errorMsg, 'Worker must post ERROR message on stream stall');
    if (errorMsg?.type === 'ERROR') {
      assert.strictEqual(errorMsg.stage, 'DOWNLOAD_COMPLETE', 'Stall after 100% must name DOWNLOAD_COMPLETE stage');
      assert.ok(errorMsg.details?.includes('DOWNLOAD_COMPLETE'), 'Error details must name DOWNLOAD_COMPLETE');
      assert.ok(errorMsg.message.includes('DOWNLOAD_COMPLETE'), 'User message must name DOWNLOAD_COMPLETE');
    }
  });

  it('Candidate 2: writable.close() never settles -> times out with stage CLOSING_FILE', async () => {
    const messages: BasemapWorkerToMainMessage[] = [];
    const chunk = new Uint8Array(100);
    const mockFs = createMockFs({ closeNeverSettles: true });

    await runBasemapInstall('nyc', '/api/basemap', {
      postMessage: (msg) => messages.push(msg),
      fetch: async () => createMockResponse(100, [chunk], false),
      getCityDirectoryHandle: mockFs.getCityDirectoryHandle,
      deletePartialFile: async () => {},
      closeStreamTimeoutMs: 30,
    });

    const errorMsg = messages.find((m) => m.type === 'ERROR');
    assert.ok(errorMsg, 'Worker must post ERROR message when writable.close() hangs');
    if (errorMsg?.type === 'ERROR') {
      assert.strictEqual(errorMsg.stage, 'CLOSING_FILE');
      assert.ok(errorMsg.details?.includes('CLOSING_FILE'));
    }
  });

  it('Candidate 3: fileHandle.getFile() never settles -> times out with stage VERIFYING', async () => {
    const messages: BasemapWorkerToMainMessage[] = [];
    const chunk = new Uint8Array(100);
    const mockFs = createMockFs({ getFileNeverSettles: true });

    await runBasemapInstall('nyc', '/api/basemap', {
      postMessage: (msg) => messages.push(msg),
      fetch: async () => createMockResponse(100, [chunk], false),
      getCityDirectoryHandle: mockFs.getCityDirectoryHandle,
      deletePartialFile: async () => {},
      getFileTimeoutMs: 30,
    });

    const errorMsg = messages.find((m) => m.type === 'ERROR');
    assert.ok(errorMsg, 'Worker must post ERROR message when getFile() hangs');
    if (errorMsg?.type === 'ERROR') {
      assert.strictEqual(errorMsg.stage, 'VERIFYING');
      assert.ok(errorMsg.details?.includes('VERIFYING'));
    }
  });

  it('Candidate 4: headerSlice.arrayBuffer() never settles -> times out with stage VERIFYING', async () => {
    const messages: BasemapWorkerToMainMessage[] = [];
    const chunk = new Uint8Array(100);
    const mockFs = createMockFs({ arrayBufferNeverSettles: true });

    await runBasemapInstall('nyc', '/api/basemap', {
      postMessage: (msg) => messages.push(msg),
      fetch: async () => createMockResponse(100, [chunk], false),
      getCityDirectoryHandle: mockFs.getCityDirectoryHandle,
      deletePartialFile: async () => {},
      readHeaderTimeoutMs: 30,
    });

    const errorMsg = messages.find((m) => m.type === 'ERROR');
    assert.ok(errorMsg, 'Worker must post ERROR message when arrayBuffer() hangs');
    if (errorMsg?.type === 'ERROR') {
      assert.strictEqual(errorMsg.stage, 'VERIFYING');
      assert.ok(errorMsg.details?.includes('VERIFYING'));
    }
  });

  it('Partial file cleanup hang in catch block does NOT prevent error message from posting', async () => {
    const messages: BasemapWorkerToMainMessage[] = [];
    const chunk = new Uint8Array(100);
    const mockFs = createMockFs({ closeNeverSettles: true });

    await runBasemapInstall('nyc', '/api/basemap', {
      postMessage: (msg) => messages.push(msg),
      fetch: async () => createMockResponse(100, [chunk], false),
      getCityDirectoryHandle: mockFs.getCityDirectoryHandle,
      deletePartialFile: () => new Promise<void>(() => {}), // cleanup hangs forever
      closeStreamTimeoutMs: 25,
      cleanupTimeoutMs: 25,
    });

    const errorMsg = messages.find((m) => m.type === 'ERROR');
    assert.ok(errorMsg, 'Worker must post ERROR message even if partial file deletion hangs');
    if (errorMsg?.type === 'ERROR') {
      assert.strictEqual(errorMsg.stage, 'CLOSING_FILE');
    }
  });

  it('Negative case: healthy complete download posts stage sequence and READY without timeout', async () => {
    const messages: BasemapWorkerToMainMessage[] = [];
    const chunk = new Uint8Array(100);
    const mockFs = createMockFs();

    await runBasemapInstall('nyc', '/api/basemap', {
      postMessage: (msg) => messages.push(msg),
      fetch: async () => createMockResponse(100, [chunk], false),
      getCityDirectoryHandle: mockFs.getCityDirectoryHandle,
      deletePartialFile: async () => {},
    });

    const errorMsg = messages.find((m) => m.type === 'ERROR');
    assert.strictEqual(errorMsg, undefined, 'Healthy download must not produce any ERROR');

    const readyMsg = messages.find((m) => m.type === 'READY');
    assert.ok(readyMsg, 'Healthy download must post READY');
    if (readyMsg?.type === 'READY') {
      assert.strictEqual(readyMsg.fileSize, 500);
    }

    // Verify stage sequence
    const stages = messages.filter((m) => m.type === 'STAGE').map((m: any) => m.stage);
    assert.deepStrictEqual(stages, [
      'STARTING_DOWNLOAD',
      'DOWNLOADING',
      'DOWNLOAD_COMPLETE',
      'CLOSING_FILE',
      'VERIFYING',
    ]);
  });

  it('Candidate 9: initial fetch fails with WebKit "Load failed" -> retries with bounded backoff and names resource in Diagnostic on exhaustion', async () => {
    const messages: BasemapWorkerToMainMessage[] = [];
    const mockFs = createMockFs();
    let fetchCalls = 0;

    await runBasemapInstall('nyc', '/api/basemap?city=nyc', {
      postMessage: (msg) => messages.push(msg),
      fetch: async () => {
        fetchCalls++;
        throw new TypeError('Load failed');
      },
      getCityDirectoryHandle: mockFs.getCityDirectoryHandle,
      deletePartialFile: async () => {},
      fetchRetries: 2,
      retryDelayMs: 5,
    });

    const errorMsg = messages.find((m) => m.type === 'ERROR');
    assert.ok(errorMsg, 'Worker must post ERROR message when fetch exhausts retries');
    if (errorMsg?.type === 'ERROR') {
      assert.strictEqual(errorMsg.stage, 'STARTING_DOWNLOAD', 'Must fail at STARTING_DOWNLOAD stage');
      assert.ok(
        errorMsg.details?.includes('/api/basemap?city=nyc'),
        `Error details must explicitly name the resource URL (got "${errorMsg.details}")`
      );
      assert.strictEqual(
        errorMsg.details?.includes('Diagnostic: Load failed\n') || errorMsg.details?.endsWith('Diagnostic: Load failed'),
        false,
        'Diagnostic must not surface raw engine message "Load failed" verbatim'
      );
    }
    assert.strictEqual(fetchCalls, 3, 'Must attempt initial fetch plus 2 bounded retries');
  });

  it('Negative case: initial fetch fails with transient "Load failed" but recovers on retry -> completes READY', async () => {
    const messages: BasemapWorkerToMainMessage[] = [];
    const chunk = new Uint8Array(100);
    const mockFs = createMockFs();
    let fetchCalls = 0;

    await runBasemapInstall('nyc', '/api/basemap?city=nyc', {
      postMessage: (msg) => messages.push(msg),
      fetch: async () => {
        fetchCalls++;
        if (fetchCalls === 1) {
          throw new TypeError('Load failed');
        }
        return createMockResponse(100, [chunk], false);
      },
      getCityDirectoryHandle: mockFs.getCityDirectoryHandle,
      deletePartialFile: async () => {},
      fetchRetries: 2,
      retryDelayMs: 5,
    });

    const errorMsg = messages.find((m) => m.type === 'ERROR');
    assert.strictEqual(errorMsg, undefined, 'Worker must not post ERROR when transient failure recovers on retry');

    const readyMsg = messages.find((m) => m.type === 'READY');
    assert.ok(readyMsg, 'Worker must complete and post READY after recovering on retry');
    assert.strictEqual(fetchCalls, 2, 'Should succeed on second attempt');
  });
});
