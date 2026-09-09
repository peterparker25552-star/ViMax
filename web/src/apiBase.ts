/*
 * Base URL for the ViMax engine bridge.
 *
 * Resolution order:
 *   1. `window.VIMAX_ENGINE_URL` — injected by the Android app (APK WebView)
 *      so the bundled UI can point at any engine address chosen in the app
 *      menu.
 *   2. Same-origin (empty base) — when the app is served BY the engine over
 *      HTTP (Termux on-device, LAN, or desktop). Relative /api/... URLs are
 *      correct for any host.
 *   3. `VITE_API_BASE` — build-time fallback for the file://-loaded APK
 *      bundle (default http://127.0.0.1:4173, a Termux engine on the same
 *      phone).
 */
declare global {
  interface Window {
    VIMAX_ENGINE_URL?: string;
  }
}

const BUNDLED_API_BASE =
  (import.meta.env?.VITE_API_BASE as string | undefined)?.replace(/\/$/, '') || '';

export const API_BASE: string =
  window.VIMAX_ENGINE_URL?.replace(/\/$/, '') ||
  (window.location.protocol === 'http:' || window.location.protocol === 'https:'
    ? ''
    : BUNDLED_API_BASE);

export function apiUrl(path: string): string {
  if (!path.startsWith('/')) return path;
  return `${API_BASE}${path}`;
}
