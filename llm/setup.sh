#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LLAMA_DIR="$ROOT_DIR/llama.cpp"
MODELS_DIR="$ROOT_DIR/models"
MODEL_FILE="$MODELS_DIR/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"

mkdir -p "$MODELS_DIR"

if [ ! -d "$LLAMA_DIR" ]; then
  git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
else
  echo "llama.cpp already present at $LLAMA_DIR"
fi

cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build"
cmake --build "$LLAMA_DIR/build" --config Release -j4

if [ ! -f "$MODEL_FILE" ]; then
  wget -O "$MODEL_FILE" "$MODEL_URL"
else
  echo "Model already exists: $MODEL_FILE"
fi

echo "Model SHA256:"
sha256sum "$MODEL_FILE"

echo "Starting llama-server on :11434"
exec "$LLAMA_DIR/build/bin/llama-server" \
  -m "$MODEL_FILE" \
  --host 0.0.0.0 --port 11434 \
  -c 2048 --threads 2 -ngl 0 \
  --chat-template qwen2
