#!/data/data/com.termux/files/usr/bin/bash
#
# Save your Google AI API key into ViMax's configuration from Termux:
#
#   bash android/set-api-key.sh
#
# Paste the key when prompted (input is hidden), press Enter, then restart
# the engine and reopen the app. This fixes:
#   RuntimeError: VIMAX_LLM_API_KEY is required for the agent LLM client
#
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

printf 'Paste your Google AI API key (input hidden), then press Enter.\n(If a key is already saved, just press Enter to keep it): '
read -rs KEY
echo

KEY="$(printf '%s' "$KEY" | tr -d '\r\n' | xargs 2>/dev/null || printf '%s' "$KEY")"

KEY="$KEY" python3 - <<'PY'
import os
from pathlib import Path

try:
    import yaml
except ImportError:
    raise SystemExit("pyyaml is missing — run: pip install pyyaml")

key = os.environ.get("KEY", "").strip()
path = Path("configs/agent.local.yaml")
data = {}
if path.exists():
    loaded = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if isinstance(loaded, dict):
        data = loaded

# LLM section: defaults match the app's "Google Gemini + Veo" quick setup,
# but any model/base_url the user already chose is preserved.
llm = data.get("llm") if isinstance(data.get("llm"), dict) else {}
llm.setdefault("model_provider", "openai")
llm.setdefault("model", "gemini-3.6-flash")
llm.setdefault("base_url", "https://generativelanguage.googleapis.com/v1beta/openai")
if key:
    llm["api_key"] = key
elif not llm.get("api_key"):
    raise SystemExit("No key entered and no key saved yet — paste your API key from https://aistudio.google.com/apikey")
data["llm"] = llm

# Image/video default to Google when not configured. The engine reuses the
# LLM key for them automatically, so no extra keys are needed here.
image = data.get("image") if isinstance(data.get("image"), dict) else {}
image.setdefault("provider", "google")
image.setdefault("model", "gemini-3.1-flash-image")
data["image"] = image

video = data.get("video") if isinstance(data.get("video"), dict) else {}
video.setdefault("provider", "google")
video.setdefault("model", "veo-3.1-generate-preview")
data["video"] = video

# Migrate retired Google model names (e.g. "models/gemini-2.5-flash is no
# longer available to new users"). Only Gemini 2.5 defaults are bumped;
# custom models from other providers are left untouched.
MIGRATIONS = {
    "llm": {"gemini-3.6-flash", "gemini-2.5-flash"},
    "image": {"gemini-3.1-flash-image", "gemini-2.5-flash-image"},
}
current_llm = str(llm.get("model") or "")
if current_llm in MIGRATIONS["llm"] - {"gemini-3.6-flash"}:
    llm["model"] = "gemini-3.6-flash"
    print(f"migrated llm model: {current_llm} -> gemini-3.6-flash")
current_image = str(image.get("model") or "")
if current_image in MIGRATIONS["image"] - {"gemini-3.1-flash-image"}:
    image["model"] = "gemini-3.1-flash-image"
    print(f"migrated image model: {current_image} -> gemini-3.1-flash-image")

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")
print(f"Saved. providers: llm={llm['model']} | image={image['model']} | video={video['model']}")
print("Key stored in configs/agent.local.yaml (kept private; git ignores it).")
PY

echo
echo "Next steps:"
echo "  1. Stop the running engine (Volume-down + C in its terminal)."
echo "  2. Start it again:        bash android/start-vimax.sh"
echo "  3. Refresh the ViMax app (pull down) and send your idea."
echo
echo "Optional check:  bash android/diagnose.sh --test-api"
