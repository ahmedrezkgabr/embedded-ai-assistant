#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BACKEND_PORT=3000
LLM_PORT=11434
LLM_THREADS=2
LLM_CTX=2048
LLM_MODEL_PATH="$PROJECT_ROOT/llm/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
WHISPER_BIN="$PROJECT_ROOT/stt/whisper.cpp/build/bin/whisper-cli"
WHISPER_MODEL="$PROJECT_ROOT/stt/models/ggml-tiny.en.bin"
PIPER_BIN="$PROJECT_ROOT/tts/bin/piper"
PIPER_VOICE="$PROJECT_ROOT/tts/models/en_US-lessac-low.onnx"
LLAMA_BIN="$PROJECT_ROOT/llm/llama.cpp/build/bin/llama-server"
BACKEND_DIR="$PROJECT_ROOT/backend"
LOG_DIR="/tmp/ai-assistant-logs"
STARTUP_TIMEOUT=120

if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  C_RESET="$(tput sgr0)"
  C_CYAN="$(tput setaf 6)"
  C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"
  C_RED="$(tput setaf 1)"
else
  C_RESET=""
  C_CYAN=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
fi

log_info() {
  echo -e "${C_CYAN}[INFO]${C_RESET} $*"
}

log_ok() {
  echo -e "${C_GREEN}[OK]${C_RESET} $*"
}

log_warn() {
  echo -e "${C_YELLOW}[WARN]${C_RESET} $*"
}

log_error() {
  echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2
}

log_step() {
  echo ""
  echo "============================================================"
  echo "$*"
  echo "============================================================"
}

LLAMA_PID=""
BACKEND_PID=""
TAIL_PID=""
SELF_TEST_OK=0
CLEANED_UP=0

kill_and_wait_if_running() {
  local pid="$1"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

cleanup() {
  if [ "$CLEANED_UP" -eq 1 ]; then
    return
  fi
  CLEANED_UP=1

  log_info "Shutting down all services..."

  kill_and_wait_if_running "${LLAMA_PID:-}"
  kill_and_wait_if_running "${BACKEND_PID:-}"

  if [ -n "${TAIL_PID:-}" ]; then
    for pid in $TAIL_PID; do
      kill_and_wait_if_running "$pid"
    done
  fi

  log_ok "All services stopped. Goodbye."
}

trap cleanup EXIT INT TERM

log_step "Running preflight checks"

[ -f "$LLAMA_BIN" ] || {
  log_error "llama-server not found at $LLAMA_BIN"
  log_error "Run:  cd llm && bash setup.sh"
  exit 1
}
log_ok "Found llama-server: $LLAMA_BIN"

[ -f "$LLM_MODEL_PATH" ] || {
  log_error "Model not found at $LLM_MODEL_PATH"
  log_error "Run:  cd llm && bash setup.sh  (to download the model)"
  exit 1
}
MODEL_SIZE=$(wc -c < "$LLM_MODEL_PATH")
[ "$MODEL_SIZE" -gt 209715200 ] || {
  log_error "Model file is too small ($MODEL_SIZE bytes) — likely corrupt"
  log_error "Delete it and re-run:  cd llm && bash setup.sh"
  exit 1
}
log_ok "Found LLM model: $LLM_MODEL_PATH (${MODEL_SIZE} bytes)"

[ -f "$WHISPER_BIN" ] || {
  log_error "whisper-cli not found at $WHISPER_BIN"
  log_error "Run:  cd stt && bash setup.sh"
  exit 1
}
log_ok "Found whisper-cli: $WHISPER_BIN"

[ -f "$WHISPER_MODEL" ] || {
  log_error "Whisper model not found at $WHISPER_MODEL"
  log_error "Run:  cd stt && bash setup.sh"
  exit 1
}
log_ok "Found Whisper model: $WHISPER_MODEL"

[ -f "$PIPER_BIN" ] || {
  log_error "piper not found at $PIPER_BIN"
  log_error "Run:  cd tts && bash setup.sh"
  exit 1
}
log_ok "Found piper: $PIPER_BIN"

[ -f "$PIPER_VOICE" ] || {
  log_error "Piper voice not found at $PIPER_VOICE"
  log_error "Run:  cd tts && bash setup.sh"
  exit 1
}
[ -f "${PIPER_VOICE}.json" ] || {
  log_error "Piper voice JSON sidecar missing: ${PIPER_VOICE}.json"
  log_error "Run:  cd tts && bash setup.sh"
  exit 1
}
log_ok "Found Piper voice model + JSON"

command -v node >/dev/null 2>&1 || {
  log_error "node not found in PATH"
  log_error "Install Node.js 24 from https://nodejs.org"
  exit 1
}
NODE_VER=$(node --version | cut -d. -f1 | tr -d 'v')
[ "$NODE_VER" -ge 18 ] || {
  log_error "Node.js v$NODE_VER is too old. Need v18 or later."
  exit 1
}
log_ok "Found Node.js: $(node --version)"

[ -d "$BACKEND_DIR/node_modules" ] || {
  log_warn "node_modules not found — running npm install..."
  (cd "$BACKEND_DIR" && npm install --silent)
  log_ok "npm install complete"
}

if [ ! -f "$BACKEND_DIR/.env" ]; then
  log_warn ".env not found — copying from .env.example"
  cp "$BACKEND_DIR/.env.example" "$BACKEND_DIR/.env"
  log_warn "Edit $BACKEND_DIR/.env if you need custom settings"
fi

for PORT in $BACKEND_PORT $LLM_PORT; do
  if lsof -ti ":$PORT" >/dev/null 2>&1; then
    OWNER=$(lsof -ti ":$PORT" | head -1)
    log_error "Port $PORT is already in use by PID $OWNER"
    log_error "Kill it with:  kill $OWNER"
    log_error "Or run:  ./stop.sh"
    exit 1
  fi
done

log_ok "All preflight checks passed"

log_step "Detecting local network IP"

LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1 || true)
if [ -z "$LOCAL_IP" ]; then
  LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
fi
if [ -z "$LOCAL_IP" ]; then
  LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || true)
fi
if [ -z "$LOCAL_IP" ]; then
  LOCAL_IP=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1 || true)
fi
if [ -z "$LOCAL_IP" ]; then
  LOCAL_IP="localhost"
  log_warn "Could not detect LAN IP — using localhost"
  log_warn "Other devices may not be able to connect"
else
  log_ok "Detected LAN IP: $LOCAL_IP"
fi

mkdir -p "$LOG_DIR"

wait_for_llama() {
  local elapsed=0
  while [ "$elapsed" -lt "$STARTUP_TIMEOUT" ]; do
    if ! kill -0 "$LLAMA_PID" 2>/dev/null; then
      log_error "llama-server exited before becoming ready"
      tail -n 20 "$LOG_DIR/llama.log" || true
      exit 1
    fi

    if curl -sf "http://localhost:$LLM_PORT/health" >/dev/null 2>&1; then
      log_ok "llama-server is ready"
      return 0
    fi

    sleep 3
    elapsed=$((elapsed + 3))
  done

  log_error "Timed out waiting for llama-server readiness (${STARTUP_TIMEOUT}s)"
  tail -n 20 "$LOG_DIR/llama.log" || true
  exit 1
}

wait_for_backend() {
  local elapsed=0
  while [ "$elapsed" -lt "$STARTUP_TIMEOUT" ]; do
    if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
      log_error "Express backend exited before becoming ready"
      tail -n 20 "$LOG_DIR/backend.log" || true
      exit 1
    fi

    if curl -sf "http://localhost:$BACKEND_PORT/api/llm/health" 2>/dev/null | python3 -c "import sys, json; d=json.load(sys.stdin); sys.exit(0 if d.get('status') == 'ok' else 1)" 2>/dev/null; then
      log_ok "Express backend is ready"
      return 0
    fi

    sleep 3
    elapsed=$((elapsed + 3))
  done

  log_error "Timed out waiting for Express backend readiness (${STARTUP_TIMEOUT}s)"
  tail -n 20 "$LOG_DIR/backend.log" || true
  exit 1
}

log_step "Starting LLM (llama-server)"

LLAMA_CMD=(
  "$LLAMA_BIN"
  -m "$LLM_MODEL_PATH"
  --host 0.0.0.0
  --port "$LLM_PORT"
  -c "$LLM_CTX"
  --threads "$LLM_THREADS"
  -ngl 0
  --chat-template qwen2
)

export LD_LIBRARY_PATH="$PROJECT_ROOT/llm/llama.cpp/build/bin:${LD_LIBRARY_PATH:-}"

"${LLAMA_CMD[@]}" > "$LOG_DIR/llama.log" 2>&1 &
LLAMA_PID=$!
log_info "llama-server started (PID $LLAMA_PID)"
log_info "Log: $LOG_DIR/llama.log"

wait_for_llama

log_step "Writing runtime backend .env"

cat > "$BACKEND_DIR/.env" << EOF
PORT=$BACKEND_PORT
LLM_BASE_URL=http://localhost:$LLM_PORT
LLM_DEFAULT_MODEL=Qwen2.5-0.5B-Instruct-Q4_K_M.gguf
LLM_TIMEOUT=60000
LLM_STRICT_SYSTEM_PROMPT=You are a helpful embedded Linux voice assistant. Always reply in English only using plain ASCII characters. Be concise and accurate.
WHISPER_BIN=$WHISPER_BIN
WHISPER_MODEL=$WHISPER_MODEL
PIPER_BIN=$PIPER_BIN
PIPER_VOICE=$PIPER_VOICE
NODE_ENV=production
EOF

log_step "Starting Express backend"

node "$BACKEND_DIR/src/server.js" > "$LOG_DIR/backend.log" 2>&1 &
BACKEND_PID=$!
log_info "Express backend started (PID $BACKEND_PID)"
log_info "Log: $LOG_DIR/backend.log"

wait_for_backend

log_step "Running self-test"

log_info "Testing LLM..."
LLM_REPLY=$(curl -sf -X POST \
  "http://localhost:$BACKEND_PORT/api/llm/chat" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"What is 1 plus 1? Reply with just the number.","options":{"temperature":0,"max_tokens":8,"seed":42}}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('response',''))" \
  2>/dev/null || echo "")

if [ -z "$LLM_REPLY" ]; then
  log_error "LLM returned empty response"
  log_error "Check $LOG_DIR/llama.log for details"
  exit 1
fi

if python3 -c "
import sys
text = open('/dev/stdin').read()
bad = [c for c in text if ord(c) > 127]
sys.exit(1 if bad else 0)
" <<< "$LLM_REPLY"; then
  log_ok "LLM test passed: '$LLM_REPLY'"
else
  log_error "LLM returned non-ASCII/non-English response: '$LLM_REPLY'"
  log_error "System prompt may not be reaching llama-server."
  log_error "Check $LOG_DIR/llama.log and backend/src/services/llmService.js"
  exit 1
fi

log_info "Testing TTS..."
TTS_SIZE=$(curl -sf -X POST \
  "http://localhost:$BACKEND_PORT/api/voice/tts" \
  -H "Content-Type: application/json" \
  -d '{"text":"System ready."}' \
  --output /tmp/ai_selftest_tts.wav \
  && wc -c < /tmp/ai_selftest_tts.wav || echo "0")

TTS_SIZE=$(echo "$TTS_SIZE" | tr -d ' ')
if [ "$TTS_SIZE" -gt 5000 ]; then
  log_ok "TTS test passed: ${TTS_SIZE} bytes"
else
  log_error "TTS returned too little data (${TTS_SIZE} bytes)"
  log_error "Check piper binary: $PIPER_BIN"
  log_error "Check voice model:  $PIPER_VOICE"
  exit 1
fi

log_info "Testing STT..."
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -f lavfi -i "sine=frequency=440:duration=1" \
    -ar 16000 -ac 1 -sample_fmt s16 \
    /tmp/ai_selftest_stt.wav -y -loglevel quiet 2>/dev/null
elif command -v sox >/dev/null 2>&1; then
  sox -n -r 16000 -c 1 /tmp/ai_selftest_stt.wav \
    synth 1 sine 440 2>/dev/null
else
  cp /tmp/ai_selftest_tts.wav /tmp/ai_selftest_stt.wav
fi

STT_RESP=$(curl -sf -X POST \
  "http://localhost:$BACKEND_PORT/api/voice/stt" \
  -F "audio=@/tmp/ai_selftest_stt.wav;type=audio/wav" \
  2>/dev/null || echo "")

if echo "$STT_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'transcript' in d else 1)" 2>/dev/null; then
  TRANSCRIPT=$(echo "$STT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript',''))")
  log_ok "STT test passed: transcript='$TRANSCRIPT'"
else
  log_error "STT returned unexpected response: $STT_RESP"
  log_error "Check whisper-cli: $WHISPER_BIN"
  exit 1
fi

log_info "Testing UI file serving..."
for UI_PATH in "/" "/style.css" "/app.js"; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$BACKEND_PORT$UI_PATH")
  if [ "$HTTP_CODE" = "200" ]; then
    log_ok "UI $UI_PATH → HTTP 200"
  else
    log_error "UI $UI_PATH → HTTP $HTTP_CODE (expected 200)"
    log_error "Ensure backend/public/ contains index.html, style.css, app.js"
    exit 1
  fi
done

SELF_TEST_OK=1

print_banner() {
  local local_url="http://localhost:$BACKEND_PORT"
  local lan_url="http://$LOCAL_IP:$BACKEND_PORT"
  local llm_line="LLM  (llama-server) -> localhost:$LLM_PORT"
  local api_line="API  (Express)      -> 0.0.0.0:$BACKEND_PORT"

  local lines=(
    "AI ASSISTANT IS READY"
    ""
    "Open in browser on THIS machine:"
    "$local_url"
    ""
    "Open from ANY device on your network:"
    "$lan_url"
    ""
    "Services running:"
    "$llm_line"
    "$api_line"
    ""
    "Press Ctrl+C to stop all services"
  )

  local max_len=0
  local line
  for line in "${lines[@]}"; do
    if [ "${#line}" -gt "$max_len" ]; then
      max_len=${#line}
    fi
  done

  local inner_width=$((max_len + 2))
  if [ "$inner_width" -lt 50 ]; then
    inner_width=50
  fi

  local border
  border=$(printf '%*s' "$inner_width" '' | tr ' ' '═')

  echo ""
  printf '╔%s╗\n' "$border"
  for line in "${lines[@]}"; do
    printf '║ %-*s ║\n' "$inner_width" "$line"
  done
  printf '╚%s╝\n' "$border"
  echo ""
}

print_banner

if [ "$SELF_TEST_OK" -eq 1 ] && [ "$LOCAL_IP" != "localhost" ]; then
  echo "NOTE: If other devices cannot connect, check your firewall:"
  echo "  Ubuntu/Debian:  sudo ufw allow $BACKEND_PORT/tcp"
  echo "  Fedora/RHEL:    sudo firewall-cmd --add-port=$BACKEND_PORT/tcp --permanent"
  echo "  macOS:          System Settings → Network → Firewall"
  echo ""
fi

log_step "Live logs"

(tail -f "$LOG_DIR/backend.log" | sed 's/^/[backend] /') &
TAIL_BACKEND_PID=$!

(tail -f "$LOG_DIR/llama.log" \
  | grep --line-buffered -E 'request|error|warning|slot|done|listening' \
  | sed 's/^/[llama]   /') &
TAIL_LLAMA_PID=$!

TAIL_PID="$TAIL_BACKEND_PID $TAIL_LLAMA_PID"

wait -n "$LLAMA_PID" "$BACKEND_PID"

if ! kill -0 "$LLAMA_PID" 2>/dev/null; then
  log_error "llama-server exited unexpectedly. See $LOG_DIR/llama.log"
fi

if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
  log_error "Express backend exited unexpectedly. See $LOG_DIR/backend.log"
fi

exit 1
