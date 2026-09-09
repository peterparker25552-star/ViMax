#!/data/data/com.termux/files/usr/bin/bash
#
# Start the ViMax engine + web workspace on an Android phone (Termux).
#
#   bash android/start-vimax.sh
#
# Serves the prebuilt web bundle (no Node build tools needed) and spawns the
# ViMax Python agent per session, exactly like `vimax web` does on a PC.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

export VIMAX_WEB_HOST="${VIMAX_WEB_HOST:-0.0.0.0}"
export VIMAX_WEB_PORT="${VIMAX_WEB_PORT:-4173}"
export VIMAX_WEB_DIST="${VIMAX_WEB_DIST:-android/app/src/main/assets/www}"
export VIMAX_WEB_CORS="${VIMAX_WEB_CORS:-on}"

# Use Termux's ffmpeg for final-video assembly (moviepy/imageio-ffmpeg's
# downloaded binaries do not run on Android).
FFMPEG_BIN="$(command -v ffmpeg || true)"
if [ -n "$FFMPEG_BIN" ]; then
  export IMAGEIO_FFMPEG_EXE="$FFMPEG_BIN"
fi

# Keep the engine alive while the screen is off / app is backgrounded.
termux-wake-lock 2>/dev/null || true

# Locate a Python that has the engine dependencies.
PYTHON_BIN=""
for candidate in "$REPO_DIR/.venv/bin/python" python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    resolved="$(command -v "$candidate")"
    if "$resolved" -c "import openai, langchain" >/dev/null 2>&1; then
      PYTHON_BIN="$resolved"
      break
    fi
  fi
done

if [ -z "$PYTHON_BIN" ]; then
  echo "Python dependencies are missing. Run: bash android/install-termux.sh"
  exit 1
fi

export VIMAX_PYTHON_CMD="$PYTHON_BIN"

echo "ViMax engine starting on http://$VIMAX_WEB_HOST:$VIMAX_WEB_PORT"
echo "Open on this phone:  http://127.0.0.1:$VIMAX_WEB_PORT"
echo "Press Ctrl+C to stop."
exec node "$REPO_DIR/web/server.mjs"
