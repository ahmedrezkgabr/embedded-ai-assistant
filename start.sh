#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$PROJECT_ROOT/backend"
ENV_FILE="$BACKEND_DIR/.env"
LOG_DIR="/tmp/ai-assistant-logs"
mkdir -p "$LOG_DIR"

LLAMA_BIN="$PROJECT_ROOT/llm/llama.cpp/build/bin/llama-server"
LLM_MODEL="$PROJECT_ROOT/llm/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
WHISPER_BIN="$PROJECT_ROOT/stt/whisper.cpp/build/bin/whisper-cli"
WHISPER_MODEL="$PROJECT_ROOT/stt/models/ggml-tiny.en.bin"
PIPER_BIN="$PROJECT_ROOT/tts/bin/piper"
PIPER_VOICE="$PROJECT_ROOT/tts/models/en_US-lessac-low.onnx"
PIPER_ESPEAK_DATA="$PROJECT_ROOT/tts/bin/espeak-ng-data"

BACKEND_PORT=3000
LLM_PORT=11434
STARTUP_TIMEOUT=120

LLAMA_PID=""
BACKEND_PID=""
TAIL_BACKEND_PID=""
TAIL_LLAMA_PID=""

check_ok=0

# ── Color setup ──────────────────────────────────────────────
# Use ANSI-C quoting ($'...') so \033 is interpreted as ESC
if command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
  CYAN=$(tput setaf 6)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  RED=$(tput setaf 1)
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
else
  CYAN=$'\033[0;36m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  RED=$'\033[0;31m'
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
fi

pass()  { printf "${GREEN}[PASS]${RESET}  %s\n" "$*"; }
fail()  { printf "${RED}[FAIL]${RESET}  %s\n" "$*"; }
info()  { printf "${CYAN}[INFO]${RESET}  %s\n" "$*"; }

cleanup() {
  [ -n "$TAIL_BACKEND_PID" ] && kill "$TAIL_BACKEND_PID" 2>/dev/null || true
  [ -n "$TAIL_LLAMA_PID" ] && kill "$TAIL_LLAMA_PID" 2>/dev/null || true
  [ -n "$BACKEND_PID" ] && kill "$BACKEND_PID" 2>/dev/null || true
  [ -n "$LLAMA_PID" ] && kill "$LLAMA_PID" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

check_port_free() {
  local port="$1"
  ! lsof -ti ":$port" >/dev/null 2>&1
}

node_version_ok() {
  command -v node >/dev/null 2>&1 || return 1
  local major
  major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
  [ "$major" -ge 18 ]
}

required_env_keys=(
  PORT
  LLM_BASE_URL
  LLM_DEFAULT_MODEL
  LLM_TIMEOUT
  LLM_STRICT_SYSTEM_PROMPT
  WHISPER_BIN
  WHISPER_MODEL
  PIPER_BIN
  PIPER_VOICE
)

check_env_keys() {
  [ -f "$ENV_FILE" ] || return 1
  local key
  for key in "${required_env_keys[@]}"; do
    grep -Eq "^${key}=" "$ENV_FILE" || return 1
  done
  return 0
}

preflight() {
  local fail_count=0

  if [ -x "$LLAMA_BIN" ]; then pass "llama-server binary exists"; else fail "llama-server missing. Fix: bash scripts/setup.sh"; fail_count=$((fail_count + 1)); fi
  if [ -f "$LLM_MODEL" ] && [ "$(wc -c < "$LLM_MODEL")" -gt 209715200 ]; then pass "Qwen model exists"; else fail "Qwen model missing/corrupt. Fix: bash scripts/setup.sh"; fail_count=$((fail_count + 1)); fi
  if [ -x "$WHISPER_BIN" ]; then pass "whisper-cli binary exists"; else fail "whisper-cli missing. Fix: bash scripts/setup.sh"; fail_count=$((fail_count + 1)); fi
  if [ -f "$WHISPER_MODEL" ] && [ "$(wc -c < "$WHISPER_MODEL")" -gt 52428800 ]; then pass "whisper model exists"; else fail "whisper model missing/corrupt. Fix: bash scripts/setup.sh"; fail_count=$((fail_count + 1)); fi
  if [ -x "$PIPER_BIN" ]; then pass "piper binary exists"; else fail "piper missing. Fix: bash scripts/setup.sh"; fail_count=$((fail_count + 1)); fi
  if [ -f "$PIPER_VOICE" ] && [ -f "${PIPER_VOICE}.json" ]; then pass "piper voice + json exist"; else fail "piper voice/json missing. Fix: bash scripts/setup.sh"; fail_count=$((fail_count + 1)); fi
  if node_version_ok; then pass "node >= 18 installed"; else fail "node >= 18 required. Fix: install Node.js"; fail_count=$((fail_count + 1)); fi
  if [ -d "$BACKEND_DIR/node_modules" ]; then pass "backend/node_modules exists"; else fail "backend dependencies missing. Fix: (cd backend && npm install)"; fail_count=$((fail_count + 1)); fi
  if [ -f "$ENV_FILE" ]; then pass "backend/.env exists"; else cp "$BACKEND_DIR/.env.example" "$ENV_FILE" && info "Created backend/.env from .env.example"; fi
  if check_env_keys; then pass "backend/.env has required keys"; else fail "backend/.env missing keys. Fix: cp backend/.env.example backend/.env"; fail_count=$((fail_count + 1)); fi
  if check_port_free "$BACKEND_PORT"; then pass "port 3000 free"; else fail "port 3000 busy. Fix: ./stop.sh"; fail_count=$((fail_count + 1)); fi
  if check_port_free "$LLM_PORT"; then pass "port 11434 free"; else fail "port 11434 busy. Fix: ./stop.sh"; fail_count=$((fail_count + 1)); fi

  if [ "$fail_count" -gt 0 ]; then
    echo "Run ./scripts/setup.sh to fix missing components"
    exit 1
  fi

  check_ok=1
}

detect_lan_ip() {
  local ip
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n 1 || true)"
  if [ -z "$ip" ]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  if [ -z "$ip" ]; then
    ip="localhost"
  fi
  echo "$ip"
}

write_env() {
  cat > "$ENV_FILE" <<EOF
PORT=$BACKEND_PORT
TMP_DIR=/tmp
UPLOAD_DIR=/tmp/ai-assistant/uploads
LOG_FILE=/tmp/ai-assistant/backend.log
LLM_BASE_URL=http://127.0.0.1:$LLM_PORT
LLM_DEFAULT_MODEL=Qwen2.5-0.5B-Instruct-Q4_K_M.gguf
LLM_TIMEOUT=60000
LLM_MAX_TOKENS=128
LLM_TEMPERATURE=0
LLM_TOP_P=0.2
LLM_FREQUENCY_PENALTY=0
LLM_PRESENCE_PENALTY=0
LLM_STRICT_SYSTEM_PROMPT=You are an embedded Linux voice assistant running offline. Always reply in English only using ASCII characters. Keep answers concise and factual.
WHISPER_BIN=$WHISPER_BIN
WHISPER_MODEL=$WHISPER_MODEL
WHISPER_TIMEOUT=30000
PIPER_BIN=$PIPER_BIN
PIPER_VOICE=$PIPER_VOICE
PIPER_VOICE_DIR=$PROJECT_ROOT/tts/models
PIPER_ESPEAK_DATA=$PIPER_ESPEAK_DATA
PIPER_TIMEOUT=20000
NODE_ENV=production
EOF
}

# ── Health check: llama-server ───────────────────────────────
wait_llama() {
  info "Waiting for llama-server..."
  local waited=0
  while [ "$waited" -lt "$STARTUP_TIMEOUT" ]; do
    sleep 2
    waited=$((waited + 2))

    # Check process is still alive
    if ! kill -0 "$LLAMA_PID" 2>/dev/null; then
      fail "llama-server process died (PID $LLAMA_PID)"
      fail "Last 20 lines of llama log:"
      tail -20 "$LOG_DIR/llama.log" >&2
      return 1
    fi

    # Try to get health response
    HEALTH_BODY=$(curl -s \
      --max-time 3 \
      --connect-timeout 2 \
      "http://127.0.0.1:${LLM_PORT}/health" \
      2>/dev/null || true)

    # Skip empty responses silently (not ready yet)
    if [ -z "$HEALTH_BODY" ]; then
      continue
    fi

    # llama-server /health returns {"status":"ok"} or just "ok"
    if echo "$HEALTH_BODY" | grep -q '"ok"\|"status":"ok"\|ok'; then
      return 0
    fi

    info "  llama-server not ready yet (${waited}s / ${STARTUP_TIMEOUT}s)..."
  done
  return 1
}

# ── Health check: Express backend ────────────────────────────
wait_backend() {
  info "Waiting for Express backend..."
  local waited=0
  local BACKEND_READY=0
  while [ "$waited" -lt "$STARTUP_TIMEOUT" ]; do
    sleep 2
    waited=$((waited + 2))

    # Check process is still alive
    if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
      fail "Express backend process died (PID $BACKEND_PID)"
      fail "Last 20 lines of backend log:"
      tail -20 "$LOG_DIR/backend.log" >&2
      return 1
    fi

    # Try to get the health response
    HEALTH_BODY=$(curl -s \
      --max-time 3 \
      --connect-timeout 2 \
      "http://127.0.0.1:${BACKEND_PORT}/api/llm/health" \
      2>/dev/null || true)

    # Skip empty responses silently (backend not ready yet)
    if [ -z "$HEALTH_BODY" ]; then
      continue
    fi

    # Parse the status field safely
    STATUS=$(echo "$HEALTH_BODY" \
      | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('status', ''))
except Exception:
    print('')
" 2>/dev/null || true)

    if [ "$STATUS" = "ok" ]; then
      BACKEND_READY=1
      break
    fi

    info "  backend not ready yet (${waited}s / ${STARTUP_TIMEOUT}s)..."
  done

  if [ "$BACKEND_READY" = "0" ]; then
    return 1
  fi
  return 0
}

# ── Smoke test ───────────────────────────────────────────────
smoke_test() {
  SMOKE_REPLY=$(curl -s \
    --max-time 30 \
    --connect-timeout 5 \
    -X POST "http://127.0.0.1:${BACKEND_PORT}/api/llm/chat" \
    -H "Content-Type: application/json" \
    -d '{"prompt":"What is 1 plus 1? Reply with just the number.","options":{"temperature":0,"max_tokens":8,"seed":42}}' \
    2>/dev/null || true)

  if [ -z "$SMOKE_REPLY" ]; then
    fail "Smoke test: empty response from backend"
    exit 1
  fi

  SMOKE_TEXT=$(echo "$SMOKE_REPLY" \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('response', ''))
except Exception as e:
    print(f'PARSE_ERROR: {e}', file=sys.stderr)
    print('')
" 2>/tmp/smoke_parse_err || true)

  if [ -z "$SMOKE_TEXT" ]; then
    fail "Smoke test: could not parse LLM response"
    fail "Raw response: $SMOKE_REPLY"
    PARSE_ERR=$(cat /tmp/smoke_parse_err 2>/dev/null || true)
    [ -n "$PARSE_ERR" ] && fail "Parse error: $PARSE_ERR"
    exit 1
  fi

  # ASCII check
  if python3 -c "
import sys
text = sys.argv[1]
bad = [c for c in text if ord(c) > 127]
sys.exit(1 if bad else 0)
" "$SMOKE_TEXT" 2>/dev/null; then
    pass "Smoke tests passed: '$SMOKE_TEXT'"
  else
    fail "Smoke test: LLM returned non-ASCII output: '$SMOKE_TEXT'"
    fail "System prompt may not be reaching llama-server."
    fail "Check LLM_STRICT_SYSTEM_PROMPT in .env and"
    fail "--chat-template chatml in llama-server startup."
    exit 1
  fi

  # TTS smoke
  local tts_size
  tts_size="$(curl -sf -X POST "http://127.0.0.1:$BACKEND_PORT/api/voice/tts" -H "Content-Type: application/json" -d '{"text":"System ready."}' --output /tmp/ai_start_smoke.wav && wc -c < /tmp/ai_start_smoke.wav)"
  if [ "$tts_size" -le 5000 ]; then
    fail "Smoke test failed (TTS size=${tts_size}). Fix: check PIPER_BIN/PIPER_VOICE in backend/.env"
    exit 1
  fi

  pass "TTS smoke test passed (${tts_size} bytes)"
}

# ── Log tailing ──────────────────────────────────────────────
start_logs() {
  touch "$LOG_DIR/backend.log" "$LOG_DIR/llama.log"

  CYAN_SED=$'\033[0;36m'
  YELLOW_SED=$'\033[0;33m'
  RESET_SED=$'\033[0m'

  tail -f "$LOG_DIR/backend.log" | sed "s/^/${CYAN_SED}[backend]${RESET_SED} /" &
  TAIL_BACKEND_PID=$!

  tail -f "$LOG_DIR/llama.log" \
    | grep --line-buffered -v \
      -e "slot update_slots" \
      -e "slot launch_slot_" \
      -e "slot init_sampler" \
      -e "sched_reserve" \
      -e "load_tensors" \
      -e "print_info:" \
      -e "llama_model_loader" \
    | sed "s/^/${YELLOW_SED}[llama]  ${RESET_SED} /" &
  TAIL_LLAMA_PID=$!
}

# ── Main ─────────────────────────────────────────────────────
preflight
LAN_IP="$(detect_lan_ip)"
write_env

"$LLAMA_BIN" -m "$LLM_MODEL" --host 0.0.0.0 --port "$LLM_PORT" -c 2048 --threads 2 -ngl 0 --chat-template chatml > "$LOG_DIR/llama.log" 2>&1 &
LLAMA_PID=$!

if ! wait_llama; then
  fail "llama-server failed to become healthy"
  exit 1
fi
pass "llama-server healthy"

(
  cd "$BACKEND_DIR"
  node src/server.js > "$LOG_DIR/backend.log" 2>&1
) &
BACKEND_PID=$!

if ! wait_backend; then
  fail "backend failed to become healthy"
  exit 1
fi
pass "backend healthy"

smoke_test

echo
echo "AI assistant ready"
echo "Local: http://localhost:$BACKEND_PORT"
echo "LAN:   http://$LAN_IP:$BACKEND_PORT"
echo

start_logs

wait -n "$LLAMA_PID" "$BACKEND_PID"
exit 1
