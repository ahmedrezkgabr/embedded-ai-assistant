#!/bin/bash
set -euo pipefail

BASE_URL="${1:-http://localhost:3000}"

echo "Checking LLM health"
curl -fsS "${BASE_URL}/api/llm/health" | cat
echo

echo "Checking voice health"
curl -fsS "${BASE_URL}/api/voice/health" | cat
echo

echo "Sending test chat"
curl -fsS -X POST "${BASE_URL}/api/llm/chat" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"say hi"}' | cat
echo

echo "Sending test TTS"
curl -fsS -X POST "${BASE_URL}/api/voice/tts" \
  -H "Content-Type: application/json" \
  -d '{"text":"hello"}' > /tmp/test.wav

echo "Saved /tmp/test.wav"
if command -v aplay >/dev/null 2>&1; then
  aplay /tmp/test.wav
else
  echo "aplay unavailable; inspect /tmp/test.wav manually"
fi
