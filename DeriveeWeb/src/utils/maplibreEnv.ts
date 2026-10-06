// Polyfill self in Node.js test environment so MapLibre worker imports do not throw ReferenceError
if (typeof globalThis.self === 'undefined') {
  (globalThis as any).self = globalThis;
}
export {};
