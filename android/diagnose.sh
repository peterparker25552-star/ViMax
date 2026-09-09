#!/data/data/com.termux/files/usr/bin/bash
#
# ViMax diagnostic — run this and paste the output when something fails:
#
#   bash android/diagnose.sh            # environment + engine + config check
#   bash android/diagnose.sh --test-api # also make a tiny live test call to your LLM
#
# Never prints your API key (only whether one is saved).
#
set -uo pipefail

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32mok\033[0m  %s\n' "$*"; }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33mwarn\033[0m %s\n' "$*"; }

cd "$(cd "$(dirname "$0")/.." && pwd)"
echo "ViMax diagnostic — $(date)"
echo "repository: $(pwd)"
echo

say "Python dependencies"
for mod in openai aiohttp langchain google.genai cryptography moviepy PIL yaml pydantic tenacity; do
  if python3 -c "import $mod" >/dev/null 2>&1; then
    ok "$mod"
  else
    # Show the real reason for the first line of failure
    reason="$(python3 -c "import $mod" 2>&1 | tail -1 | cut -c1-120)"
    bad "$mod — $reason"
  fi
done
echo

say "Node web runtime"
if command -v node >/dev/null 2>&1; then
  ok "node $(node --version)"
else
  bad "node not found (pkg install nodejs-lts)"
fi
if [ -d web/node_modules/yaml ]; then
  ok "web runtime deps installed (yaml)"
else
  bad "web runtime deps missing — run: bash android/start-vimax.sh   (installs them automatically)"
fi
echo

say "Engine bridge"
HEALTH="$(curl -s --max-time 3 http://127.0.0.1:4173/api/health 2>/dev/null)"
if [ -n "$HEALTH" ]; then
  ok "http://127.0.0.1:4173 — $HEALTH"
else
  bad "engine not reachable on port 4173 — start it with: bash android/start-vimax.sh"
fi
echo

say "Provider configuration (configs/agent.local.yaml)"
python3 - <<'PY'
import os, re
path = os.path.join("configs", "agent.local.yaml")
if not os.path.exists(path):
    print("  FAIL no config file yet — open Settings in the app, use Quick setup, Save")
else:
    text = open(path).read()
    sections = ["llm", "image", "video", "embedding", "reranker"]
    any_key = False
    current = None
    values = {}
    for line in text.splitlines():
        head = re.match(r'^(\w+):\s*$', line)
        kv = re.match(r'^\s{2}(\w+):\s*(.*)$', line)
        if head:
            current = head.group(1)
        elif kv and current:
            values[(current, kv.group(1))] = kv.group(2).strip()
    for section in sections:
        model = values.get((section, "model"), "")
        provider = values.get((section, "provider"), values.get((section, "model_provider"), ""))
        key = values.get((section, "api_key"), "")
        status = "key saved" if key else "NO KEY"
        if key:
            any_key = True
        print(f"  {section:9s} provider={provider or '-':12s} model={model or '-':38s} {status}")
    if not any_key:
        print("  FAIL no API key saved anywhere — Settings -> Quick setup -> Google Gemini + Veo -> paste key -> Save")
    env_key = os.environ.get("VIMAX_LLM_API_KEY") or os.environ.get("VIMAX_API_KEY")
    if env_key:
        print(f"  env      VIMAX_LLM_API_KEY is also set in this shell")
PY
echo

say "Recent agent log"
LOG_DIR=".vimax/logs"
if [ -d "$LOG_DIR" ] && [ -n "$(ls -A "$LOG_DIR" 2>/dev/null)" ]; then
  LATEST="$(ls -t "$LOG_DIR" | head -1)"
  echo "  (last 15 lines of $LOG_DIR/$LATEST)"
  tail -15 "$LOG_DIR/$LATEST" | sed 's/^/    /'
else
  warn "no agent logs yet"
fi
echo

if [ "${1:-}" = "--test-api" ]; then
  say "Live LLM test call (tiny, uses your saved key)"
  python3 - <<'PY'
import asyncio, os, sys
sys.path.insert(0, os.getcwd())
os.environ.setdefault("VIMAX_LLM_API_KEY", "")
from agent_runtime import config
model, base_url, key = config.llm_model("."), config.llm_base_url("."), config.llm_api_key(".")
if not key:
    print("  FAIL no LLM API key saved")
    sys.exit(0)
from openai import AsyncOpenAI
async def main():
    client = AsyncOpenAI(api_key=key, base_url=base_url, timeout=30)
    try:
        r = await client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": "Reply with the single word: OK"}],
            max_completion_tokens=2000,
        )
        text = (r.choices[0].message.content or "").strip()
        print(f"  ok   {model} replied: {text[:40]!r}")
    except Exception as e:
        msg = str(e).splitlines()[0][:220]
        print(f"  FAIL {model} via {base_url}")
        print(f"       {msg}")
asyncio.run(main())
PY
  echo
fi

say "Done — paste everything above (no secrets are included) when asking for help."
