#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$ROOT_DIR/bin"
MODELS_DIR="$ROOT_DIR/models"
PIPER_ARCHIVE="$BIN_DIR/piper.tar.gz"
PIPER_SRC_DIR="$ROOT_DIR/piper-src"
BUILD_ONLY="${1:-}"

mkdir -p "$BIN_DIR" "$MODELS_DIR"

if [ "$BUILD_ONLY" = "--build-only" ]; then
  if [ ! -d "$PIPER_SRC_DIR" ]; then
    git clone --depth 1 https://github.com/rhasspy/piper.git "$PIPER_SRC_DIR"
  else
    echo "piper source already present at $PIPER_SRC_DIR"
  fi

  git -C "$PIPER_SRC_DIR" submodule update --init --recursive

  cmake -S "$PIPER_SRC_DIR" -B "$PIPER_SRC_DIR/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$PIPER_SRC_DIR/build" --config Release -j4

  PIPER_PATH="$(find "$PIPER_SRC_DIR/build" -type f -name piper | head -n 1)"
  if [ -z "$PIPER_PATH" ]; then
    echo "Unable to locate built piper binary"
    exit 1
  fi

  cp "$PIPER_PATH" "$BIN_DIR/piper"
  chmod +x "$BIN_DIR/piper"
  find "$PIPER_SRC_DIR/build" -type f -name '*.so*' -exec cp -n {} "$BIN_DIR"/ \;

  ESPEAK_DATA_PHONTAB="$(find "$PIPER_SRC_DIR/build" -type f -path '*/espeak-ng-data/phontab' | head -n 1 || true)"
  if [ -n "${ESPEAK_DATA_PHONTAB:-}" ] && [ -f "$ESPEAK_DATA_PHONTAB" ]; then
    ESPEAK_DATA_DIR="$(dirname "$ESPEAK_DATA_PHONTAB")"
    mkdir -p "$BIN_DIR/espeak-ng-data"
    cp -a "$ESPEAK_DATA_DIR"/. "$BIN_DIR/espeak-ng-data"/
  fi

  ESPEAK_SO_PATH="$(ldd "$BIN_DIR/piper" | awk '/libespeak-ng\.so\.1/{print $3; exit}')"
  if [ -n "${ESPEAK_SO_PATH:-}" ] && [ -f "$ESPEAK_SO_PATH" ]; then
    ESPEAK_SO_REAL="$(readlink -f "$ESPEAK_SO_PATH")"
    cp -n "$ESPEAK_SO_REAL" "$BIN_DIR/"
    ln -sfn "$(basename "$ESPEAK_SO_REAL")" "$BIN_DIR/libespeak-ng.so.1"
  fi

  echo "Build-only mode: skipping model download and audio test"
  exit 0
fi

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
  PIPER_DIST_DIR="$(dirname "$PIPER_PATH")"
  cp -a "$PIPER_DIST_DIR"/. "$BIN_DIR"/
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
