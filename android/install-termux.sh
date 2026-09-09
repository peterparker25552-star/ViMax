#!/data/data/com.termux/files/usr/bin/bash
#
# ViMax on Android — one-shot installer for the Termux app.
#
#   1. Install Termux from F-Droid (https://f-droid.org/en/packages/com.termux/).
#   2. Get this repository onto the phone, then run:
#        bash android/install-termux.sh
#
# The script installs Termux packages and the ViMax Python engine
# dependencies (all API clients — nothing heavy, no torch). Nothing is
# uploaded anywhere; generation calls the AI providers you configure
# (Google Gemini + Veo by default).
#
set -euo pipefail

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m ==\033[0m %s\n' "$*"; }

if [ ! -d "/data/data/com.termux/files/usr" ]; then
  echo "This installer is for the Termux app on Android. On a PC use: uv sync"
  exit 1
fi

say "Installing Termux packages (5-15 minutes on the first run)…"
pkg update -y
pkg install -y \
  python python-pip \
  git nodejs-lts \
  binutils build-essential rust \
  python-numpy python-pillow \
  python-cryptography \
  ffmpeg

# pip-built cryptography wheels fail to load on Termux
# ("dlopen failed: cannot locate symbol ... _rust.abi3.so") because they are
# not linked against Termux's Python. Termux's own package is built
# correctly, so replace any broken pip copy with it.
if ! python3 -c 'import cryptography' >/dev/null 2>&1; then
  warn "cryptography is broken (common Termux/pip issue) — switching to the Termux build…"
  pip uninstall -y cryptography >/dev/null 2>&1 || true
  pkg install -y python-cryptography
fi
if python3 -c 'import cryptography' >/dev/null 2>&1; then
  say "cryptography OK ($(python3 -c 'import cryptography; print(cryptography.__version__)'))."
else
  warn "cryptography is still unavailable — Google Gemini/Veo generation will fail."
fi

# Optional: enables multi-camera transition analysis (scene detection).
if pkg install -y python-opencv 2>/dev/null; then
  say "OpenCV installed — camera-transition analysis enabled."
  OPTIONAL_PIP="scenedetect"
else
  warn "python-opencv unavailable; multi-camera transitions will be skipped (everything else works)."
  OPTIONAL_PIP=""
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"
say "ViMax repository: $REPO_DIR"

say "Upgrading Python tooling…"
pip install --upgrade pip setuptools wheel

say "Installing ViMax Python dependencies…"
warn "pydantic-core compiles native code with Rust — 10-40 minutes on a phone, once only."
# Versions mirror the repository's uv.lock so behaviour matches desktop.
pip install \
  "openai>=1.95.0" \
  "aiohttp>=3.12.14" \
  "chardet>=5.2.0" \
  "google-genai==1.47.0" \
  "langchain==0.3.26" \
  "langchain-community==0.3.27" \
  "langchain-openai==0.3.27" \
  "langchain-text-splitters==0.3.8" \
  "moviepy==2.2.1" \
  "pydantic>=2" \
  "pyyaml>=6.0.2" \
  "requests>=2.32.4" \
  "tenacity>=9.1.2" \
  $OPTIONAL_PIP

say "Verifying the engine boots (this is exactly what the app runs)…"
BOOT_LOG="$(mktemp)"
if VIMAX_LLM_API_KEY=boot-check python3 - >"$BOOT_LOG" 2>&1 <<'PY'
import os, sys
sys.path.insert(0, os.getcwd())
from agent_runtime import build_runtime
build_runtime(".")
print("  ok  agent runtime builds")
import moviepy, google.genai  # noqa: E401
print("  ok  video assembly + Google AI clients")
PY
then
  cat "$BOOT_LOG"
  rm -f "$BOOT_LOG"
else
  echo "$BOOT_LOG" | tail -20
  rm -f "$BOOT_LOG"
  warn "Engine boot failed. Common fixes:"
  warn "  - cryptography dlopen error:  pip uninstall -y cryptography && pkg install -y python-cryptography"
  warn "  - missing packages:           re-run this installer"
  exit 1
fi

cat <<'DONE'

ViMax is installed on this phone. ✔

Next steps
----------
1. Start the engine + web app:
     bash android/start-vimax.sh

2. Open http://127.0.0.1:4173 in Chrome on this phone.

3. Add it to your home screen: Chrome menu (⋮) -> "Add to Home screen".

4. In the app: Settings -> Quick setup -> "Google Gemini + Veo",
   paste your Google AI API key (https://aistudio.google.com/apikey),
   then Save. Create a project and describe your video!

Notes
-----
- Keep Termux running in the background (don't swipe it away); the start
  script takes a wake-lock so Android won't kill the engine.
- Idea2Video and Script2Video work fully on the phone. Novel2Video needs
  the faiss library, which is not available on Termux — run novel
  projects on a computer instead.
DONE
