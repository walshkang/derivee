export function isFatalMapError(err: Error | any): boolean {
  if (!err) return false;

  // MapLibre AJAX errors for missing tiles/glyphs are usually 404s
  if (typeof err.status === 'number') {
    if (err.status === 404 || err.status === 403) {
      return false;
    }
  }

  const msg = (err.message || '').toLowerCase();
  
  if (
    msg.includes('status 404') ||
    msg.includes('status 403') ||
    msg.includes('could not load glyphs') ||
    msg.includes('could not load tile') ||
    msg.includes('could not load image') ||
    msg.includes('failed to load tile') ||
    msg.includes('failed to load glyphs')
  ) {
    return false;
  }

  return true;
}

/**
 * Formats map worker errors to include the attempted worker URL in the diagnostic message.
 * If the error message mentions "worker" and does not already include the attempted URL,
 * the URL is appended for troubleshooting.
 */
export function formatMapWorkerError(err: unknown, attemptedWorkerUrl: string): Error {
  const baseMessage =
    err instanceof Error
      ? err.message
      : err && typeof err === 'object' && 'message' in err
        ? String((err as any).message)
        : String(err || 'Map error');

  if (
    baseMessage.toLowerCase().includes('worker') &&
    attemptedWorkerUrl &&
    !baseMessage.includes(attemptedWorkerUrl)
  ) {
    return new Error(`${baseMessage} (Worker URL: ${attemptedWorkerUrl})`);
  }
  return err instanceof Error ? err : new Error(baseMessage);
}

