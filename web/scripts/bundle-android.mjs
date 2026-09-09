#!/usr/bin/env node
/*
 * Build the ViMax web app for bundling inside the Android APK.
 *
 *   node scripts/bundle-android.mjs [engine-url]
 *
 * The bundle is written to android/app/src/main/assets/www. The engine URL
 * (default http://127.0.0.1:4173 for a Termux engine on the same phone) is
 * baked in via VITE_API_BASE; users can change it later from the app menu.
 */
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const webRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const apiBase = (process.argv[2] || 'http://127.0.0.1:4173').replace(/\/$/, '');
const npx = process.platform === 'win32' ? 'npx.cmd' : 'npx';

console.log(`Bundling ViMax web app for Android (engine: ${apiBase})…`);
const result = spawnSync(npx, ['vite', 'build', '--base', './', '--outDir', '../android/app/src/main/assets/www', '--emptyOutDir'], {
  stdio: 'inherit',
  cwd: webRoot,
  env: {...process.env, VITE_API_BASE: apiBase},
});
process.exit(result.status ?? 1);
