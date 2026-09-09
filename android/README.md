# ViMax for Android

Three ways to use ViMax on an Android phone — pick the one that matches
where the **engine** (the Python part that calls the AI providers) runs:

| Setup | Engine location | What to do |
|---|---|---|
| **A. Everything on the phone** | the phone (Termux) | [Install the engine in Termux](#a-everything-on-the-phone-termux), install the APK or PWA, connect to `http://127.0.0.1:4173` |
| **B. Engine on a PC/server** | a computer on the same Wi-Fi | Run `vimax web` on the PC, install the APK or PWA, connect to `http://<pc-ip>:4173` |
| **C. PWA only** | a PC/server (or phone+Termux) | Skip the APK: open the engine's address in Chrome → *Add to Home screen* |

The APK is a lightweight, native-feeling shell around the ViMax web
workspace (webview + file upload/download integration, keep-screen-on for
long renders, configurable engine address). All the intelligence — scripts,
storyboards, image/video generation, final assembly — stays in the ViMax
engine and your chosen AI providers.

---

## Getting the APK

### Option 1 — download a prebuilt APK from GitHub Actions (recommended)

1. Open the repo on GitHub → **Actions** → **Android APK**.
2. Click **Run workflow** → **Run** (any branch that contains `android/`).
3. When the run finishes, download **ViMax-android-debug-apk** from the
   run's *Artifacts* section.
4. Copy `app-debug.apk` to your phone and install it
   (allow "install unknown apps" for your file manager).

### Option 2 — build it yourself (any Linux/macOS/WSL machine)

Requirements: Node.js 18+, JDK 17, Android SDK (command-line tools are
enough), Gradle 8.7+.

```bash
# 1. Bundle the web app into the APK assets
cd web && npm install && npm run bundle:android && cd ..

# 2. Build
gradle -p android assembleDebug        # or: ./gradlew if you have the wrapper
# APK: android/app/build/outputs/apk/debug/app-debug.apk
```

CI (`.github/workflows/android-apk.yml`) does exactly these two steps.

---

## A. Everything on the phone (Termux)

1. Install **Termux** from F-Droid.
2. Get ViMax onto the phone and install:
   ```bash
   git clone https://github.com/peterparker25552-star/ViMax.git
   cd ViMax
   bash android/install-termux.sh    # 15-45 min first time (native builds)
   ```
3. Start the engine:
   ```bash
   bash android/start-vimax.sh       # serves http://0.0.0.0:4173
   ```
4. Open `http://127.0.0.1:4173` in Chrome → *Add to Home screen*, or install
   the APK and keep the default engine address `http://127.0.0.1:4173`.
5. In the app: **Settings → Quick setup → Google Gemini + Veo**, paste your
   API key(s), **Save**. Then create a project and describe your video.

Tips for phone use:
- `termux-wake-lock` (run by the start script) keeps the engine alive while
  the screen is off. Keep Termux in the background, don't swipe it away.
- Long videos consume battery + data: renders happen on the provider's
  cloud, but the phone uploads/downloads frames and clips.
- The app menu → **Keep screen on while rendering** prevents Android from
  freezing the webview during long generations.

## B. Engine on a PC, app on the phone

1. On the PC: `uv sync`, configure `configs/agent.local.yaml`, then
   `vimax web` (or `npm run start` in `web/`). The console prints the
   LAN address, e.g. `http://192.168.1.20:4173`.
2. On the phone: install the APK → menu (⋮) → **Engine connection…** →
   enter `http://192.168.1.20:4173` (and keep "bundled UI" checked), or
   simply open the address in Chrome and *Add to Home screen*.

## Engine address & the bundled UI

The APK bundles the ViMax web app. Before the page runs, the app injects
your configured engine address (`window.VIMAX_ENGINE_URL`), so the bundled
UI talks to any engine you choose in **Engine connection…**. You can also
switch to loading the engine's own copy of the UI directly (useful if the
phone and the engine versions drift apart).
