#!/data/data/com.termux/files/usr/bin/bash
#
# ViMax on Android — one-shot installer for the Termux app.
#
#   1. Install Termux from F-Droid (https://f-droid.org/en/packages/com.termux/).
#   2. Copy this repository onto the phone (or clone it), then run:
#        bash android/install-termux.sh
#
# The script installs Termux packages, the ViMax Python engine dependencies
# (all API clients — no heavy native ML stacks), and verifies the setup.
# Nothing is uploaded anywhere; generation calls the AI providers you
# configure (Google Gemini + Veo by default).
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
  ffmpeg

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"
say "ViMax repository: $REPO_DIR"

say "Upgrading Python tooling…"
pip install --upgrade pip setuptools wheel

say "Installing ViMax Python dependencies…"
warn "pydantic-core and tiktoken compile native code with Rust — this can take 15-40 minutes on a phone. It only happens once."
pip install \
  "openai>=1.95.0" \
  "aiohttp>=3.12.14" \
  "chardet>=5.2.0" \
  "google-genai>=1.47.0" \
  "langchain>=0.3.26" \
  "langchain-community>=0.3.27" \
  "langchain-openai>=0.3.27" \
  "langchain-text-splitters" \
  "pyyaml>=6.0.2" \
  "requests>=2.32.4" \
  "tenacity>=9.1.2"

say "Checking the engine imports cleanly…"
python3 - <<'PY'
import importlib
for module in ("openai", "aiohttp", "langchain", "google.genai", "yaml", "tenacity", "PIL"):
    importlib.import_module(module)
    print(f"  ok  {module}")
PY

cat <<'DONE'

ViMax is installed on this phone.

Next steps
----------
1. Start the engine + web app:
     bash android/start-vimax.sh

2. Open the workspace in this phone's browser:
     http://127.0.0.1:4173

3. Install the home-screen app: open the same address in Chrome,
   menu (⋮) -> "Add to Home screen" / "Install app".

4. Configure AI providers in the app's Settings screen
   (Google Gemini + Veo quick-setup preset included) or edit
   configs/agent.local.yaml directly.

Notes
-----
- opencv/scenedetect are optional in this build; multi-camera
  transition analysis is skipped automatically when absent.
- For the full feature set on a computer, keep using: uv sync
DONE
