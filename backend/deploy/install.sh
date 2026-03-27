#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND_SRC="$ROOT_DIR/backend"
LLM_MODELS_SRC="$ROOT_DIR/llm/models"
STT_MODELS_SRC="$ROOT_DIR/stt/models"
TTS_MODELS_SRC="$ROOT_DIR/tts/models"
BIN_STT="$ROOT_DIR/stt/whisper.cpp/build/bin/whisper-cli"
BIN_TTS="$ROOT_DIR/tts/bin/piper"

sudo mkdir -p /opt/ai-assistant/backend
sudo mkdir -p /opt/ai-assistant/models

echo "Copying backend..."
sudo rsync -a --delete \
  --exclude node_modules \
  --exclude uploads \
  --exclude .env \
  "$BACKEND_SRC/" /opt/ai-assistant/backend/

echo "Copying models..."
if [ -d "$LLM_MODELS_SRC" ]; then
  sudo cp -f "$LLM_MODELS_SRC"/*.gguf /opt/ai-assistant/models/ 2>/dev/null || true
fi
if [ -d "$STT_MODELS_SRC" ]; then
  sudo cp -f "$STT_MODELS_SRC"/*.bin /opt/ai-assistant/models/ 2>/dev/null || true
fi
if [ -d "$TTS_MODELS_SRC" ]; then
  sudo cp -f "$TTS_MODELS_SRC"/*.onnx* /opt/ai-assistant/models/ 2>/dev/null || true
fi

echo "Installing binaries..."
if [ -x "$BIN_STT" ]; then
  sudo install -m 0755 "$BIN_STT" /usr/local/bin/whisper-cli
fi
if [ -x "$BIN_TTS" ]; then
  sudo install -m 0755 "$BIN_TTS" /usr/local/bin/piper
fi

echo "Installing node modules..."
cd /opt/ai-assistant/backend
sudo npm install --omit=dev

echo "Installing systemd units..."
sudo install -m 0644 "$ROOT_DIR/llm/llama-server.service" /etc/systemd/system/llama-server.service
sudo install -m 0644 "$BACKEND_SRC/deploy/ai-assistant.service" /etc/systemd/system/ai-assistant.service

sudo systemctl daemon-reload
sudo systemctl enable llama-server.service
sudo systemctl enable ai-assistant.service
sudo systemctl restart llama-server.service || true
sudo systemctl restart ai-assistant.service || true

echo "Deployment complete. Access at http://<ip>:3000"
