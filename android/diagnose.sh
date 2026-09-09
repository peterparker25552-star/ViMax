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
        base = values.get((section, "base_url"), "")
        key = values.get((section, "api_key"), "")
        if key:
            any_key = True
            # Show only the prefix family — that reveals a swapped key
            # (Google keys start with AIza, Groq keys with gsk_) safely.
            kind = "Google" if key.startswith("AIza") else "Groq" if key.startswith("gsk_") else "unknown format"
            keyinfo = f"key={key[:4]}…{key[-4:]} ({kind}, {len(key)} chars)"
        else:
            keyinfo = "no key (falls back to the llm key)"
        target = base or ("Google direct" if provider == "google" else provider or "-")
        print(f"  {section:9s} -> {target[:42]:42s} {keyinfo}")
    if not any_key:
        print("  FAIL no API key saved anywhere - run: bash android/set-api-key.sh")
    print("  note: a Google key (AIza…) must go with Google URLs; a Groq key (gsk_…) only with api.groq.com")
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
  say "Live LLM test call (tiny, uses your saved key - measures latency)"
  python3 - <<'PY'
import asyncio, os, sys, time
sys.path.insert(0, os.getcwd())
os.environ.setdefault("VIMAX_LLM_API_KEY", "")
from agent_runtime import config
model, base_url, key = config.llm_model("."), config.llm_base_url("."), config.llm_api_key(".")
effort = config.llm_reasoning_effort(".")
if not key:
    print("  FAIL no LLM API key saved")
    sys.exit(0)
from openai import AsyncOpenAI
async def main():
    client = AsyncOpenAI(api_key=key, base_url=base_url, timeout=60)
    try:
        t0 = time.perf_counter()
        kwargs = dict(
            model=model,
            messages=[{"role": "user", "content": "Reply with the single word: OK"}],
            max_completion_tokens=2000,
        )
        if effort:
            kwargs["reasoning_effort"] = effort
        r = await client.chat.completions.create(**kwargs)
        dt = time.perf_counter() - t0
        text = (r.choices[0].message.content or "").strip()
        print(f"  ok   {model} replied: {text[:40]!r} in {dt:.1f}s (reasoning_effort={effort or 'default'})")
        if dt > 25:
            print("       slow: Google needed >25s for a trivial prompt - that is")
            print("       network latency to Google from your connection, not ViMax.")
    except Exception as e:
        msg = str(e).splitlines()[0][:220]
        print(f"  FAIL {model} via {base_url}")
        print(f"       {msg}")
asyncio.run(main())
PY
  echo
fi

say "Done — paste everything above (no secrets are included) when asking for help."
