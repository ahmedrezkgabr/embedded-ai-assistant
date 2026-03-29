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

red='\033[0;31m'
green='\033[0;32m'
cyan='\033[0;36m'
reset='\033[0m'

pass() { echo -e "${green}[PASS]${reset} $*"; }
fail() { echo -e "${red}[FAIL]${reset} $*"; }
info() { echo -e "${cyan}[INFO]${reset} $*"; }

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

wait_llama() {
  local waited=0
  while [ "$waited" -lt "$STARTUP_TIMEOUT" ]; do
    if curl -sf "http://127.0.0.1:$LLM_PORT/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}

wait_backend() {
  local waited=0
  while [ "$waited" -lt "$STARTUP_TIMEOUT" ]; do
    if curl -sf "http://127.0.0.1:$BACKEND_PORT/api/llm/health" | python3 -c "import json,sys; print('ok' if json.load(sys.stdin).get('status')=='ok' else 'bad')" | grep -q ok; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}

smoke_test() {
  local llm_resp
  llm_resp="$(curl -sf -X POST "http://127.0.0.1:$BACKEND_PORT/api/llm/chat" -H "Content-Type: application/json" -d '{"prompt":"What is 1 plus 1? Reply with just the number.","options":{"temperature":0,"max_tokens":8,"seed":42}}' | python3 -c "import json,sys; print(json.load(sys.stdin).get('response',''))")"
  if [ -z "$llm_resp" ] || ! python3 - "$llm_resp" <<'PY'
import sys
text=sys.argv[1]
sys.exit(0 if text and all(ord(c)<128 for c in text) else 1)
PY
  then
    fail "Smoke test failed (LLM English/ASCII). Fix: check LLM_STRICT_SYSTEM_PROMPT and --chat-template qwen2"
    exit 1
  fi

  local tts_size
  tts_size="$(curl -sf -X POST "http://127.0.0.1:$BACKEND_PORT/api/voice/tts" -H "Content-Type: application/json" -d '{"text":"System ready."}' --output /tmp/ai_start_smoke.wav && wc -c < /tmp/ai_start_smoke.wav)"
  if [ "$tts_size" -le 5000 ]; then
    fail "Smoke test failed (TTS size=${tts_size}). Fix: check PIPER_BIN/PIPER_VOICE in backend/.env"
    exit 1
  fi

  pass "Smoke tests passed"
}

start_logs() {
  touch "$LOG_DIR/backend.log" "$LOG_DIR/llama.log"

  tail -f "$LOG_DIR/backend.log" | sed 's/^/\033[0;36m[backend]\033[0m /' &
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
    | sed 's/^/\033[0;33m[llama]  \033[0m /' &
  TAIL_LLAMA_PID=$!
}

preflight
LAN_IP="$(detect_lan_ip)"
write_env

"$LLAMA_BIN" -m "$LLM_MODEL" --host 0.0.0.0 --port "$LLM_PORT" -c 2048 --threads 2 -ngl 0 --chat-template qwen2 > "$LOG_DIR/llama.log" 2>&1 &
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
