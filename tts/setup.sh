#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$ROOT_DIR/bin"
MODELS_DIR="$ROOT_DIR/models"
PIPER_ARCHIVE="$BIN_DIR/piper.tar.gz"

mkdir -p "$BIN_DIR" "$MODELS_DIR"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)
    PIPER_URL="https://github.com/rhasspy/piper/releases/latest/download/piper_linux_x86_64.tar.gz"
    ;;
  aarch64)
    PIPER_URL="https://github.com/rhasspy/piper/releases/latest/download/piper_linux_aarch64.tar.gz"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

if [ ! -x "$BIN_DIR/piper" ]; then
  TMP_EXTRACT_DIR="$BIN_DIR/.extract"
  rm -rf "$TMP_EXTRACT_DIR"
  mkdir -p "$TMP_EXTRACT_DIR"
  wget -O "$PIPER_ARCHIVE" "$PIPER_URL"
  tar -xzf "$PIPER_ARCHIVE" -C "$TMP_EXTRACT_DIR"
  PIPER_PATH="$(find "$TMP_EXTRACT_DIR" -type f -name piper | head -n 1)"
  if [ -z "$PIPER_PATH" ]; then
    echo "Unable to locate piper binary in archive"
    exit 1
  fi
  cp "$PIPER_PATH" "$BIN_DIR/piper"
  chmod +x "$BIN_DIR/piper"
  rm -rf "$TMP_EXTRACT_DIR"
  rm -f "$PIPER_ARCHIVE"
else
  echo "Piper binary already exists at $BIN_DIR/piper"
fi

wget -O "$MODELS_DIR/en_US-lessac-low.onnx" \
  "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/low/en_US-lessac-low.onnx"

wget -O "$MODELS_DIR/en_US-lessac-low.onnx.json" \
  "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/low/en_US-lessac-low.onnx.json"

echo "Voice model SHA256:"
sha256sum "$MODELS_DIR/en_US-lessac-low.onnx"

echo "Hello from your embedded assistant." | \
  "$BIN_DIR/piper" --model "$MODELS_DIR/en_US-lessac-low.onnx" --output_file /tmp/test.wav

if command -v aplay >/dev/null 2>&1; then
  aplay /tmp/test.wav
else
  echo "aplay not found; test WAV written to /tmp/test.wav"
fi
