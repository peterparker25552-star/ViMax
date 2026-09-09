# 📱 ViMax on Mobile (Android)

ViMax is now an **installable Android app**. You get:

- **A real APK** (`android/`) — install it from GitHub Actions or build it
  yourself. Native shell: home-screen icon, file upload/download, offline
  banner, keep-screen-on during renders, configurable engine address.
- **An installable PWA** — open the ViMax workspace in Chrome and
  *Add to Home screen*: manifest, icons, offline shell, and standalone
  window without building anything.
- **A phone-only setup** — the entire ViMax engine can run on the phone
  itself inside [Termux](https://f-droid.org/en/packages/com.termux/); no
  computer needed.

Read [`android/README.md`](android/README.md) for the full walkthrough.

---

## How it fits together

```
┌─────────────────────────── Android phone ───────────────────────────┐
│                                                                     │
│   ViMax app (APK webview / installed PWA)                           │
│   └── talks HTTP+SSE to →  ViMax engine bridge (Node, port 4173)    │
│                              └── spawns →  ViMax agent (Python)     │
│                                              └── calls AI providers │
│                                                  (Gemini, Veo, …)   │
└─────────────────────────────────────────────────────────────────────┘
```

The engine can run in the same Termux instance (address
`http://127.0.0.1:4173`) or on any computer the phone can reach
(`http://<computer-ip>:4173`). The web bridge now sends permissive CORS
headers on `/api/*` (disable with `VIMAX_WEB_CORS=off`) so the app can
connect across origins.

## Quick start (phone-only)

```bash
# In Termux:
git clone https://github.com/peterparker25552-star/ViMax.git
cd ViMax
bash android/install-termux.sh     # installs packages + Python deps
bash android/start-vimax.sh        # engine + app on http://127.0.0.1:4173
```

Then open `http://127.0.0.1:4173` in Chrome → *Add to Home screen*, or
install the APK from **GitHub Actions → Android APK**.

Configure providers once in **Settings → Quick setup → Google Gemini +
Veo**, paste your Google AI API key, **Save** — then create a project and
describe the video you want. Everything else works exactly like the
desktop ViMax: projects, agent chat, artifacts, storyboard previews, and
final renders (tap a rendered video to watch or download it).

## Speed on phones

- **Fast chat brains** (pick in `android/set-api-key.sh` or Settings):
  - *Gemini Flash-Lite* — fastest Google model, works with the same free
    Google key (`llm.model: gemini-3.5-flash-lite`).
  - *Groq GPT-OSS 120B* — often faster than ChatGPT's first token; free key
    at console.groq.com (no credit card). Set the Groq key under Agent LLM
    and keep your Google key under Image/Video (they still use Google).
- **Thinking models**: Gemini 3.x reasons silently for 30-60s before the
  first token. Setup defaults `llm.reasoning_effort: low`
  (tune it in Settings → Agent LLM → *Reasoning effort*: `low` = fastest,
  blank = provider default).
- **Images and video never get "ChatGPT-fast"** — they are different
  models rendering pixels. For cheaper/faster video clips try
  `video.model: veo-3.1-lite` if your key allows it.
- **Don't background Termux**: Android freezes background apps — keep the
  Termux screen open (or split-screen) while using ViMax, disable battery
  optimization for Termux, and leave the wake-lock the start script takes.
- **First message after starting the engine is slow**: the AI stack loads
  on first use; later replies are much faster.
- **Measure it**: `bash android/diagnose.sh --test-api` prints how long
  Google itself takes to answer a trivial prompt from your network.

## What changed in the repo for mobile

| Change | Where |
|---|---|
| PWA manifest + service worker + icons | `web/public/` |
| Install prompt, engine status card, safe-area & touch polish | `web/src/` |
| CORS + LAN banner + `VIMAX_WEB_DIST` on the bridge | `web/server.mjs` |
| Google Gemini + Veo provider routing (`image/video.provider: google`) | `agent_runtime/` |
| Lazy OpenCV/scenedetect/moviepy imports (phone-friendly engine) | `agents/`, `utils/`, `interfaces/` |
| Android APK project (webview shell) | `android/` |
| Termux installer + start scripts | `android/*.sh` |
| CI workflow that builds the APK | `.github/workflows/android-apk.yml` |
