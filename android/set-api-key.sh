#!/data/data/com.termux/files/usr/bin/bash
#
# Configure ViMax's AI on Android (Termux):
#
#   bash android/set-api-key.sh
#
# Lets you pick a fast "brain" for chat and saves your API key(s) to
# configs/agent.local.yaml. Note: image/video generation always uses Google
# (Gemini image + Veo), so the Google key is needed in every mode.
#
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

echo "Chat brain speed (this is what answers your messages):"
echo "  1) Gemini Flash-Lite  — fastest Google, uses your existing Google key (recommended)"
echo "  2) Gemini Flash       — better story quality, a bit slower"
echo "  3) Groq GPT-OSS 120B  — fastest overall (needs a free key from console.groq.com)"
printf 'Choose 1/2/3 (Enter = 1): '
read -r BRAIN
BRAIN="${BRAIN:-1}"

echo
printf 'Paste your Google AI API key (https://aistudio.google.com/apikey).\n(input hidden; press Enter to keep an already-saved key): '
read -rs GOOGLE_KEY
echo

GROQ_KEY=""
if [ "$BRAIN" = "3" ]; then
  printf 'Paste your Groq API key (https://console.groq.com/keys) — input hidden: '
  read -rs GROQ_KEY
  echo
fi

# Catch the most common mistake up front: keys pasted into the wrong slot.
case "$GOOGLE_KEY" in
  gsk_*) echo "That's a Groq key (it starts with 'gsk_'). The GOOGLE key starts with 'AIza' — get/copy it at https://aistudio.google.com/apikey"; exit 1 ;;
esac
case "$GROQ_KEY" in
  AIza*) echo "That's a Google key (it starts with 'AIza'). The GROQ key starts with 'gsk_' — get/copy it at https://console.groq.com/keys"; exit 1 ;;
esac

BRAIN="$BRAIN" GOOGLE_KEY="$GOOGLE_KEY" GROQ_KEY="$GROQ_KEY" python3 - <<'PY'
import os
from pathlib import Path

try:
    import yaml
except ImportError:
    raise SystemExit("pyyaml is missing — run: pip install pyyaml")

google_key = os.environ.get("GOOGLE_KEY", "").strip()
groq_key = os.environ.get("GROQ_KEY", "").strip()
brain = os.environ.get("BRAIN", "1").strip() or "1"

path = Path("configs/agent.local.yaml")
data = {}
if path.exists():
    loaded = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if isinstance(loaded, dict):
        data = loaded

def section(name: str) -> dict:
    value = data.get(name)
    return value if isinstance(value, dict) else {}

llm = section("llm")
image = section("image")
video = section("video")

GOOGLE_OPENAI_BASE = "https://generativelanguage.googleapis.com/v1beta/openai"

if brain == "3":
    # Groq brain; Google still needed for images/video.
    if not groq_key and not llm.get("api_key"):
        raise SystemExit("No Groq key entered — get a free one at https://console.groq.com/keys")
    if groq_key:
        llm["api_key"] = groq_key
    llm.update({
        "model_provider": "openai",
        "model": "openai/gpt-oss-120b",
        "base_url": "https://api.groq.com/openai/v1",
        "reasoning_effort": "low",
    })
    # Images/video use Google: pin the Google key explicitly so nothing
    # falls back to the Groq key.
    if not google_key and not (image.get("api_key") or video.get("api_key")):
        raise SystemExit("Google key also needed for image/video generation (Veo).")
    if google_key:
        image["api_key"] = google_key
        video["api_key"] = google_key
    brain_label = "Groq gpt-oss-120b"
else:
    # Google brain: one key for everything.
    if google_key:
        llm["api_key"] = google_key
    elif not llm.get("api_key"):
        raise SystemExit("No key entered and no key saved yet — paste your API key from https://aistudio.google.com/apikey")
    llm.update({
        "model_provider": "openai",
        "model": "gemini-3.5-flash-lite" if brain == "1" else "gemini-3.6-flash",
        "base_url": GOOGLE_OPENAI_BASE,
        "reasoning_effort": "low",
    })
    brain_label = llm["model"]

# Migrate retired Google model names if the user had them saved.
RETIRED = {"gemini-2.5-flash", "gemini-2.5-flash-image"}
if str(image.get("model") or "") in RETIRED:
    image["model"] = "gemini-3.1-flash-image"
if str(video.get("model") or "") in RETIRED:
    video["model"] = "veo-3.1-generate-preview"

image.setdefault("provider", "google")
image.setdefault("model", "gemini-3.1-flash-image")
video.setdefault("provider", "google")
video.setdefault("model", "veo-3.1-generate-preview")

# A Groq key can never authenticate to Google. If one ended up in the
# image/video slots (easy paste mistake), remove it so the engine falls
# back to the Google key — otherwise image/video generation 400s.
for section in (image, video):
    if str(section.get("api_key") or "").startswith("gsk_"):
        del section["api_key"]
        print("removed a Groq key (gsk_…) from the Google image/video config — it would always fail there")

# Reattach: on a fresh config the section dicts are detached from `data`.
data["llm"] = llm
data["image"] = image
data["video"] = video

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")

def mask(value: str) -> str:
    if not value:
        return "(no key — reuses the LLM key)"
    return f"{value[:4]}…{value[-4:]} ({len(value)} chars)"

print()
print(f"Saved. chat brain: {brain_label}")
print(f"       llm key:    {mask(str(llm.get('api_key') or ''))} -> {llm.get('base_url')}")
print(f"       images:     {image.get('model')} with key {mask(str(image.get('api_key') or ''))} (Google)")
print(f"       videos:     {video.get('model')} with key {mask(str(video.get('api_key') or ''))} (Google)")
print("Tips: for faster video clips try video model 'veo-3.1-lite' in Settings (if your key allows it).")
print("Key(s) stored in configs/agent.local.yaml (private; git ignores it).")
PY

echo
echo "Next steps:"
echo "  1. Stop the running engine (Volume-down + C in its terminal)."
echo "  2. Start it again:        bash android/start-vimax.sh"
echo "  3. Refresh the ViMax app (pull down) and send a message."
echo
echo "Speed check:  bash android/diagnose.sh --test-api"
