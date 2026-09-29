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
