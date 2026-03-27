#!/bin/bash
set -euo pipefail

echo "Checking LLM health"
curl -s http://localhost:3000/api/llm/health | cat
echo

echo "Checking voice health"
curl -s http://localhost:3000/api/voice/health | cat
echo

echo "Sending test chat"
curl -s -X POST http://localhost:3000/api/llm/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt":"say hi"}' | cat
echo

echo "Sending test TTS"
curl -s -X POST http://localhost:3000/api/voice/tts \
  -H "Content-Type: application/json" \
  -d '{"text":"hello"}' > /tmp/test.wav

echo "Saved /tmp/test.wav"
if command -v aplay >/dev/null 2>&1; then
  aplay /tmp/test.wav
else
  echo "aplay unavailable; inspect /tmp/test.wav manually"
fi
