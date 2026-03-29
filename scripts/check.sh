#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/backend/.env"

LLAMA_BIN="$PROJECT_ROOT/llm/llama.cpp/build/bin/llama-server"
LLM_MODEL="$PROJECT_ROOT/llm/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
WHISPER_BIN="$PROJECT_ROOT/stt/whisper.cpp/build/bin/whisper-cli"
WHISPER_MODEL="$PROJECT_ROOT/stt/models/ggml-tiny.en.bin"
PIPER_BIN="$PROJECT_ROOT/tts/bin/piper"
PIPER_MODEL="$PROJECT_ROOT/tts/models/en_US-lessac-low.onnx"
PIPER_MODEL_JSON="$PROJECT_ROOT/tts/models/en_US-lessac-low.onnx.json"

PASS=0
TOTAL=13

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

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
  PIPER_TIMEOUT
)

print_check() {
  local ok="$1"
  local label="$2"
  if [ "$ok" = "1" ]; then
    echo -e "${GREEN}[PASS]${RESET} $label"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}[FAIL]${RESET} $label"
  fi
}

check_port_free() {
  local port="$1"
  ! lsof -ti ":$port" >/dev/null 2>&1
}

node_version_ok() {
  if ! command -v node >/dev/null 2>&1; then
    return 1
  fi
  local major
  major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
  [ "$major" -ge 18 ]
}

env_has_required_keys() {
  [ -f "$ENV_FILE" ] || return 1
  local key
  for key in "${required_env_keys[@]}"; do
    grep -Eq "^${key}=" "$ENV_FILE" || return 1
  done
  return 0
}

print_check "$( [ -x "$LLAMA_BIN" ] && echo 1 || echo 0 )" "llama-server binary exists and is executable"
print_check "$( [ -f "$LLM_MODEL" ] && [ "$(wc -c < "$LLM_MODEL")" -gt 209715200 ] && echo 1 || echo 0 )" "Qwen2.5 model file exists, size > 200 MB"
print_check "$( [ -x "$WHISPER_BIN" ] && echo 1 || echo 0 )" "whisper-cli binary exists and is executable"
print_check "$( [ -f "$WHISPER_MODEL" ] && [ "$(wc -c < "$WHISPER_MODEL")" -gt 52428800 ] && echo 1 || echo 0 )" "ggml-tiny.en.bin model exists, size > 50 MB"
print_check "$( [ -x "$PIPER_BIN" ] && echo 1 || echo 0 )" "piper binary exists and is executable"
print_check "$( [ -f "$PIPER_MODEL" ] && [ "$(wc -c < "$PIPER_MODEL")" -gt 5242880 ] && echo 1 || echo 0 )" "en_US-lessac-low.onnx exists, size > 5 MB"
print_check "$( [ -f "$PIPER_MODEL_JSON" ] && echo 1 || echo 0 )" "en_US-lessac-low.onnx.json exists"
print_check "$( node_version_ok && echo 1 || echo 0 )" "node is installed, version >= 18"
print_check "$( [ -d "$PROJECT_ROOT/backend/node_modules" ] && echo 1 || echo 0 )" "backend/node_modules exists"
print_check "$( [ -f "$ENV_FILE" ] && echo 1 || echo 0 )" "backend/.env exists"
print_check "$( env_has_required_keys && echo 1 || echo 0 )" "backend/.env has all required keys"
print_check "$( check_port_free 3000 && echo 1 || echo 0 )" "port 3000 is free"
print_check "$( check_port_free 11434 && echo 1 || echo 0 )" "port 11434 is free"

echo
echo "$PASS/$TOTAL checks passed"
if [ "$PASS" -lt "$TOTAL" ]; then
  echo "Run ./scripts/setup.sh to fix missing components"
  exit 1
fi

echo "System ready. Run ./start.sh to start."
