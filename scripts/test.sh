#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://localhost:3000"
if [ "${1:-}" = "--base-url" ] && [ -n "${2:-}" ]; then
  BASE_URL="$2"
fi

TMP_DIR="/tmp/ai-assistant-test"
mkdir -p "$TMP_DIR"

pass_count=0

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

status=()
notes=()

ascii_only() {
  python3 - "$1" <<'PY'
import sys
text = sys.argv[1]
print('1' if all(ord(c) < 128 for c in text) else '0')
PY
}

mark() {
  local idx="$1"
  local name="$2"
  local ok="$3"
  local note="${4:-}"
  if [ "$ok" = "1" ]; then
    status[$idx]="PASS"
    pass_count=$((pass_count + 1))
  else
    status[$idx]="FAIL"
  fi
  notes[$idx]="$note"
}

# TEST 1
if curl -sf "$BASE_URL/api/llm/health" > "$TMP_DIR/t1.json"; then
  ok="$(python3 - <<'PY'
import json
with open('/tmp/ai-assistant-test/t1.json') as f:
    data = json.load(f)
print('1' if data.get('status') == 'ok' else '0')
PY
)"
  mark 1 "Backend health" "$ok" "Is start.sh running?"
else
  mark 1 "Backend health" "0" "Is start.sh running?"
fi

# TEST 2
LLM_REPLY=""
if curl -sf -X POST "$BASE_URL/api/llm/chat" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"What is 1 plus 1? Reply with just the number.","options":{"temperature":0,"max_tokens":8,"seed":42}}' > "$TMP_DIR/t2.json"; then
  LLM_REPLY="$(python3 - <<'PY'
import json
with open('/tmp/ai-assistant-test/t2.json') as f:
    data = json.load(f)
print(data.get('response',''))
PY
)"
  if [ -n "$LLM_REPLY" ] && [ "$(ascii_only "$LLM_REPLY")" = "1" ]; then
    mark 2 "LLM English reply" "1" "reply='$LLM_REPLY'"
  else
    mark 2 "LLM English reply" "0" "Check LLM_STRICT_SYSTEM_PROMPT in backend/.env and --chat-template qwen2 in start.sh"
  fi
else
  mark 2 "LLM English reply" "0" "Check LLM_STRICT_SYSTEM_PROMPT in backend/.env and --chat-template qwen2 in start.sh"
fi

# TEST 3
if curl -sN -X POST "$BASE_URL/api/llm/stream" \
  -H "Accept: text/event-stream" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Say one word."}' > "$TMP_DIR/t3.sse"; then
  token_lines="$(grep -c '^data: ' "$TMP_DIR/t3.sse" || true)"
  last_line="$(grep '^data: ' "$TMP_DIR/t3.sse" | tail -n 1 || true)"
  tokens_ok="$(python3 - <<'PY'
import json
import re
ok = True
for line in open('/tmp/ai-assistant-test/t3.sse', 'r', encoding='utf8', errors='ignore'):
    if not line.startswith('data: '):
        continue
    payload = line[6:].strip()
    if not payload:
        continue
    try:
        obj = json.loads(payload)
    except Exception:
        continue
    token = obj.get('token','')
    if any(ord(c) >= 128 for c in token):
        ok = False
        break
print('1' if ok else '0')
PY
)"
  if [ "$token_lines" -ge 1 ] && [ "$last_line" = 'data: {"done":true}' ] && [ "$tokens_ok" = "1" ]; then
    mark 3 "SSE streaming" "1"
  else
    mark 3 "SSE streaming" "0" "Check llmController.js stream() function"
  fi
else
  mark 3 "SSE streaming" "0" "Check llmController.js stream() function"
fi

# TEST 4
TTS_CODE="$(curl -s -o "$TMP_DIR/t4.wav" -w "%{http_code}" -X POST "$BASE_URL/api/voice/tts" \
  -H "Content-Type: application/json" \
  -d '{"text":"Hello from the test suite."}')"
if [ "$TTS_CODE" = "200" ]; then
  size="$(wc -c < "$TMP_DIR/t4.wav")"
  mime="$(file -b "$TMP_DIR/t4.wav" || true)"
  ctype="$(curl -sI -X POST "$BASE_URL/api/voice/tts" -H "Content-Type: application/json" -d '{"text":"ct"}' | tr -d '\r' | grep -i '^Content-Type:' | awk '{print $2}' | tr -d '\n' || true)"
  if [ "$size" -gt 5000 ] && echo "$mime" | grep -qi 'RIFF.*WAVE' && echo "$ctype" | grep -qi 'audio/wav'; then
    mark 4 "TTS synthesis" "1" "(${size} bytes)"
  else
    mark 4 "TTS synthesis" "0" "Check PIPER_BIN and PIPER_VOICE in backend/.env"
  fi
else
  mark 4 "TTS synthesis" "0" "Check PIPER_BIN and PIPER_VOICE in backend/.env"
fi

# TEST 5
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -f lavfi -i "sine=frequency=440:duration=2" -ar 16000 -ac 1 -sample_fmt s16 "$TMP_DIR/t5.wav" -y -loglevel quiet
else
  sox -n -r 16000 -c 1 "$TMP_DIR/t5.wav" synth 2 sine 440 >/dev/null 2>&1
fi

T5_CODE="$(curl -s -o "$TMP_DIR/t5.json" -w "%{http_code}" -X POST "$BASE_URL/api/voice/stt" -F "audio=@$TMP_DIR/t5.wav;type=audio/wav")"
if [ "$T5_CODE" = "200" ]; then
  transcript="$(python3 - <<'PY'
import json
with open('/tmp/ai-assistant-test/t5.json') as f:
    data = json.load(f)
print(data.get('transcript',''))
PY
)"
  key_ok="$(python3 - <<'PY'
import json
with open('/tmp/ai-assistant-test/t5.json') as f:
    data = json.load(f)
print('1' if 'transcript' in data else '0')
PY
)"
  if [ "$key_ok" = "1" ]; then
    mark 5 "STT transcription" "1" "transcript='$transcript'"
  else
    mark 5 "STT transcription" "0" "Check WHISPER_BIN and WHISPER_MODEL in backend/.env"
  fi
else
  mark 5 "STT transcription" "0" "Check WHISPER_BIN and WHISPER_MODEL in backend/.env"
fi

# TEST 6
round_ok=1
round_note=""

if ! curl -sf -X POST "$BASE_URL/api/voice/tts" -H "Content-Type: application/json" -d '{"text":"What is the capital of France?"}' --output "$TMP_DIR/t6_q.wav"; then
  round_ok=0; round_note="step 1 failed"
fi

if [ "$round_ok" = "1" ]; then
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -i "$TMP_DIR/t6_q.wav" -ar 16000 -ac 1 -sample_fmt s16 "$TMP_DIR/t6_q16.wav" -y -loglevel quiet || { round_ok=0; round_note="step 2 failed"; }
  else
    sox "$TMP_DIR/t6_q.wav" -r 16000 -c 1 "$TMP_DIR/t6_q16.wav" >/dev/null 2>&1 || { round_ok=0; round_note="step 2 failed"; }
  fi
fi

if [ "$round_ok" = "1" ]; then
  if ! curl -sf -X POST "$BASE_URL/api/voice/stt" -F "audio=@$TMP_DIR/t6_q16.wav;type=audio/wav" > "$TMP_DIR/t6_stt.json"; then
    round_ok=0; round_note="step 3 failed"
  fi
fi

if [ "$round_ok" = "1" ]; then
  t6_transcript="$(python3 - <<'PY'
import json
with open('/tmp/ai-assistant-test/t6_stt.json') as f:
    data = json.load(f)
print(data.get('transcript',''))
PY
)"
  if ! curl -sf -X POST "$BASE_URL/api/llm/chat" -H "Content-Type: application/json" -d "{\"prompt\":\"${t6_transcript//\"/\\\"}\"}" > "$TMP_DIR/t6_llm.json"; then
    round_ok=0; round_note="step 4 failed"
  fi
fi

if [ "$round_ok" = "1" ]; then
  t6_reply="$(python3 - <<'PY'
import json
with open('/tmp/ai-assistant-test/t6_llm.json') as f:
    data = json.load(f)
print(data.get('response',''))
PY
)"
  if ! echo "$t6_reply" | grep -qi 'paris' || [ "$(ascii_only "$t6_reply")" != "1" ]; then
    round_ok=0; round_note="step 5 failed reply='$t6_reply'"
  fi
fi

if [ "$round_ok" = "1" ]; then
  if ! curl -sf -X POST "$BASE_URL/api/voice/tts" -H "Content-Type: application/json" -d "{\"text\":\"${t6_reply//\"/\\\"}\"}" --output "$TMP_DIR/t6_reply.wav"; then
    round_ok=0; round_note="step 6 failed"
  fi
fi

if [ "$round_ok" = "1" ]; then
  t6_size="$(wc -c < "$TMP_DIR/t6_reply.wav")"
  if [ "$t6_size" -le 5000 ]; then
    round_ok=0; round_note="step 7 failed size=$t6_size"
  fi
fi

if [ "$round_ok" = "1" ]; then
  mark 6 "Voice round-trip" "1" "reply='${t6_reply}'"
else
  mark 6 "Voice round-trip" "0" "$round_note"
fi

# TEST 7
ui_ok=1
for p in / /style.css /app.js; do
  c="$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$p")"
  [ "$c" = "200" ] || ui_ok=0
done
if [ "$ui_ok" = "1" ]; then
  mark 7 "UI files" "1"
else
  mark 7 "UI files" "0" "Ensure backend/public/ contains all three files"
fi

# TEST 8
lcode="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/api/llm/chat" -H "Content-Type: application/json" -d '{"prompt":""}')"
tcode="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/api/voice/tts" -H "Content-Type: application/json" -d '{"text":""}')"
if { [ "$lcode" = "400" ] || [ "$lcode" = "422" ]; } && { [ "$tcode" = "400" ] || [ "$tcode" = "422" ]; }; then
  mark 8 "Input validation" "1"
else
  mark 8 "Input validation" "0" "Check validate.js middleware is mounted in app.js"
fi

echo "TEST 1  Backend health      [${status[1]}] ${notes[1]}"
echo "TEST 2  LLM English reply   [${status[2]}] ${notes[2]}"
echo "TEST 3  SSE streaming       [${status[3]}] ${notes[3]}"
echo "TEST 4  TTS synthesis       [${status[4]}] ${notes[4]}"
echo "TEST 5  STT transcription   [${status[5]}] ${notes[5]}"
echo "TEST 6  Voice round-trip    [${status[6]}] ${notes[6]}"
echo "TEST 7  UI files            [${status[7]}] ${notes[7]}"
echo "TEST 8  Input validation    [${status[8]}] ${notes[8]}"
echo "─────────────────────────────────"
echo "$pass_count/8 tests passed"

if [ "$pass_count" -eq 8 ]; then
  exit 0
fi

exit 1
