#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
START_TS="$(date +%s)"

LLAMA_DIR="$PROJECT_ROOT/llm/llama.cpp"
LLAMA_BIN="$LLAMA_DIR/build/bin/llama-server"
LLM_MODEL_DIR="$PROJECT_ROOT/llm/models"
LLM_MODEL_FILE="$LLM_MODEL_DIR/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
LLM_MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"

WHISPER_DIR="$PROJECT_ROOT/stt/whisper.cpp"
WHISPER_BIN="$WHISPER_DIR/build/bin/whisper-cli"
WHISPER_MODEL_DIR="$PROJECT_ROOT/stt/models"
WHISPER_MODEL_FILE="$WHISPER_MODEL_DIR/ggml-tiny.en.bin"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"

TTS_BIN_DIR="$PROJECT_ROOT/tts/bin"
PIPER_BIN="$TTS_BIN_DIR/piper"
PIPER_ARCHIVE="$PROJECT_ROOT/tts/piper_release.tar.gz"
TTS_MODEL_DIR="$PROJECT_ROOT/tts/models"
TTS_MODEL_ONNX="$TTS_MODEL_DIR/en_US-lessac-low.onnx"
TTS_MODEL_JSON="$TTS_MODEL_DIR/en_US-lessac-low.onnx.json"
TTS_MODEL_ONNX_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/low/en_US-lessac-low.onnx"
TTS_MODEL_JSON_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/low/en_US-lessac-low.onnx.json"

BACKEND_DIR="$PROJECT_ROOT/backend"
ENV_FILE="$BACKEND_DIR/.env"
ENV_EXAMPLE="$BACKEND_DIR/.env.example"

BUILT=()
SKIPPED=()

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_dependencies() {
  local missing=0

  for cmd in cmake make gcc g++ git python3; do
    if ! need_cmd "$cmd"; then
      echo "Missing dependency: $cmd"
      echo "Fix: sudo apt-get install -y build-essential cmake git python3"
      missing=1
    fi
  done

  if ! need_cmd wget && ! need_cmd curl; then
    echo "Missing dependency: wget or curl"
    echo "Fix: sudo apt-get install -y wget"
    missing=1
  fi

  if ! ldconfig -p 2>/dev/null | grep -q libespeak-ng; then
    echo "Missing dependency: libespeak-ng-dev"
    echo "Fix: sudo apt-get install -y libespeak-ng-dev"
    missing=1
  fi

  if ! need_cmd ffmpeg && ! need_cmd sox; then
    echo "Missing dependency: ffmpeg or sox"
    echo "Fix: sudo apt-get install -y ffmpeg"
    missing=1
  fi

  if [ "$missing" -eq 1 ]; then
    exit 1
  fi
}

download_file() {
  local url="$1"
  local dest="$2"

  if need_cmd wget; then
    wget --show-progress -O "$dest" "$url"
  else
    curl -L --progress-bar -o "$dest" "$url"
  fi
}

build_llama() {
  mkdir -p "$PROJECT_ROOT/llm" "$LLM_MODEL_DIR"

  if [ ! -d "$LLAMA_DIR/.git" ]; then
    git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
    BUILT+=("llama.cpp clone")
  else
    SKIPPED+=("llama.cpp clone")
  fi

  cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" -DLLAMA_BUILD_SERVER=ON -DLLAMA_NATIVE=OFF
  cmake --build "$LLAMA_DIR/build" --config Release -j"$(nproc)"

  if [ ! -x "$LLAMA_BIN" ]; then
    echo "llama-server build failed"
    echo "Fix: rerun bash scripts/setup.sh"
    exit 1
  fi

  BUILT+=("llama-server binary")
}

download_llm_model() {
  mkdir -p "$LLM_MODEL_DIR"
  if [ -f "$LLM_MODEL_FILE" ]; then
    local size
    size="$(wc -c < "$LLM_MODEL_FILE")"
    if [ "$size" -gt 209715200 ]; then
      SKIPPED+=("Qwen2.5 model")
      return
    fi
  fi

  download_file "$LLM_MODEL_URL" "$LLM_MODEL_FILE"
  local size
  size="$(wc -c < "$LLM_MODEL_FILE")"
  if [ "$size" -le 209715200 ]; then
    echo "Downloaded model is too small: ${size} bytes"
    echo "Fix: remove $LLM_MODEL_FILE and rerun bash scripts/setup.sh"
    exit 1
  fi

  BUILT+=("Qwen2.5 model")
}

build_whisper() {
  mkdir -p "$PROJECT_ROOT/stt" "$WHISPER_MODEL_DIR"

  if [ ! -d "$WHISPER_DIR/.git" ]; then
    git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
    BUILT+=("whisper.cpp clone")
  else
    SKIPPED+=("whisper.cpp clone")
  fi

  cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build"
  cmake --build "$WHISPER_DIR/build" -j"$(nproc)"

  if [ ! -x "$WHISPER_BIN" ]; then
    echo "whisper-cli build failed"
    echo "Fix: rerun bash scripts/setup.sh"
    exit 1
  fi

  BUILT+=("whisper-cli binary")
}

download_whisper_model() {
  mkdir -p "$WHISPER_MODEL_DIR"

  if [ -f "$WHISPER_MODEL_FILE" ]; then
    SKIPPED+=("ggml-tiny.en.bin")
    return
  fi

  download_file "$WHISPER_MODEL_URL" "$WHISPER_MODEL_FILE"
  BUILT+=("ggml-tiny.en.bin")
}

download_piper_binary() {
  mkdir -p "$TTS_BIN_DIR"

  if [ -x "$PIPER_BIN" ]; then
    SKIPPED+=("piper binary")
    return
  fi

  local arch
  arch="$(uname -m)"
  local url

  case "$arch" in
    x86_64)
      url="https://github.com/rhasspy/piper/releases/latest/download/piper_linux_x86_64.tar.gz"
      ;;
    aarch64)
      url="https://github.com/rhasspy/piper/releases/latest/download/piper_linux_aarch64.tar.gz"
      ;;
    *)
      echo "Unsupported architecture: $arch"
      echo "Fix: use x86_64 or aarch64 machine"
      exit 1
      ;;
  esac

  download_file "$url" "$PIPER_ARCHIVE"

  local extract_dir
  extract_dir="$PROJECT_ROOT/tts/.extract"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"

  tar -xzf "$PIPER_ARCHIVE" -C "$extract_dir"
  local src_bin
  src_bin="$(find "$extract_dir" -type f -name piper | head -n 1)"
  if [ -z "$src_bin" ]; then
    echo "piper binary not found in release archive"
    echo "Fix: remove $PIPER_ARCHIVE and rerun bash scripts/setup.sh"
    exit 1
  fi

  cp -a "$(dirname "$src_bin")"/. "$TTS_BIN_DIR"/
  chmod +x "$PIPER_BIN"
  rm -rf "$extract_dir" "$PIPER_ARCHIVE"

  if [ ! -x "$PIPER_BIN" ]; then
    echo "piper extraction failed"
    echo "Fix: rerun bash scripts/setup.sh"
    exit 1
  fi

  BUILT+=("piper binary")
}

download_tts_models() {
  mkdir -p "$TTS_MODEL_DIR"

  if [ -f "$TTS_MODEL_ONNX" ] && [ -f "$TTS_MODEL_JSON" ]; then
    SKIPPED+=("piper voice model")
    return
  fi

  download_file "$TTS_MODEL_ONNX_URL" "$TTS_MODEL_ONNX"
  download_file "$TTS_MODEL_JSON_URL" "$TTS_MODEL_JSON"
  BUILT+=("piper voice model")
}

install_backend_deps() {
  if [ -d "$BACKEND_DIR/node_modules" ] && [ -f "$BACKEND_DIR/package-lock.json" ] && [ "$BACKEND_DIR/package-lock.json" -ot "$BACKEND_DIR/node_modules" ]; then
    SKIPPED+=("backend npm install")
    return
  fi

  (cd "$BACKEND_DIR" && npm install)
  BUILT+=("backend npm install")
}

ensure_env() {
  if [ -f "$ENV_FILE" ]; then
    SKIPPED+=("backend .env")
  else
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    BUILT+=("backend .env")
  fi
}

require_dependencies
build_llama
download_llm_model
build_whisper
download_whisper_model
download_piper_binary
download_tts_models
install_backend_deps
ensure_env

END_TS="$(date +%s)"
ELAPSED="$((END_TS - START_TS))"

echo
echo "Built:"
for item in "${BUILT[@]:-}"; do
  [ -n "$item" ] && echo "  - $item"
done

echo "Skipped:"
for item in "${SKIPPED[@]:-}"; do
  [ -n "$item" ] && echo "  - $item"
done

echo "Total time: ${ELAPSED}s"
echo "Setup complete. Run ./start.sh to start."
