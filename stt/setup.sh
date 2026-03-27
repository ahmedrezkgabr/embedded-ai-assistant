#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_DIR="$ROOT_DIR/whisper.cpp"
MODELS_DIR="$ROOT_DIR/models"
MODEL_FILE="$MODELS_DIR/ggml-tiny.en.bin"

mkdir -p "$MODELS_DIR"

if [ ! -d "$WHISPER_DIR" ]; then
  git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
else
  echo "whisper.cpp already present at $WHISPER_DIR"
fi

cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build"
cmake --build "$WHISPER_DIR/build" -j4

if [ ! -f "$MODEL_FILE" ]; then
  bash "$WHISPER_DIR/models/download-ggml-model.sh" tiny.en
  cp "$WHISPER_DIR/models/ggml-tiny.en.bin" "$MODEL_FILE"
else
  echo "Model already exists: $MODEL_FILE"
fi

echo "Model SHA256:"
sha256sum "$MODEL_FILE"

echo "Test command (requires test.wav in $ROOT_DIR):"
echo "$WHISPER_DIR/build/bin/whisper-cli -m $MODEL_FILE -f $ROOT_DIR/test.wav -otxt"
