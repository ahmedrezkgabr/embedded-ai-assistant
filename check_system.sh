#!/usr/bin/env bash
set -euo pipefail

LLM_MODEL_PATH="${LLM_MODEL_PATH:-/usr/share/models/qwen.gguf}"
WHISPER_MODEL_PATH="${WHISPER_MODEL_PATH:-/usr/share/models/ggml-tiny.en.bin}"
PIPER_VOICE_PATH="${PIPER_VOICE_PATH:-/usr/share/models/en_US-lessac-low.onnx}"

WHISPER_BIN="${WHISPER_BIN:-/usr/bin/whisper-cli}"
PIPER_BIN="${PIPER_BIN:-/usr/bin/piper}"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  echo "[PASS] $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "[FAIL] $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

check_file_readable() {
  local label="$1"
  local target="$2"
  if [[ -r "$target" ]]; then
    pass "$label exists and is readable: $target"
  else
    fail "$label missing or unreadable: $target"
  fi
}

check_executable() {
  local label="$1"
  local target="$2"
  if [[ -x "$target" ]]; then
    pass "$label executable: $target"
  else
    fail "$label missing execute permission: $target"
  fi
}

check_alsa() {
  local ok=true

  if [[ ! -e /proc/asound/cards ]]; then
    fail "ALSA not available: /proc/asound/cards missing"
    return
  fi

  if ! grep -qE '[0-9]+ \[' /proc/asound/cards 2>/dev/null; then
    fail "ALSA detected but no audio cards listed"
    return
  fi

  if command -v aplay >/dev/null 2>&1; then
    if aplay -l >/dev/null 2>&1; then
      pass "ALSA playback device listing available"
    else
      ok=false
      fail "aplay exists but cannot list playback devices"
    fi
  else
    ok=false
    fail "aplay not found (install alsa-utils for diagnostics)"
  fi

  if command -v arecord >/dev/null 2>&1; then
    if arecord -l >/dev/null 2>&1; then
      pass "ALSA capture device listing available"
    else
      ok=false
      fail "arecord exists but cannot list capture devices"
    fi
  else
    ok=false
    fail "arecord not found (install alsa-utils for diagnostics)"
  fi

  if [[ "$ok" == true ]]; then
    pass "ALSA core readiness checks passed"
  fi
}

echo "=== Embedded AI Assistant System Check ==="
echo "Date: $(date -Iseconds)"

check_alsa
check_executable "whisper-cli" "$WHISPER_BIN"
check_executable "piper" "$PIPER_BIN"
check_file_readable "LLM model" "$LLM_MODEL_PATH"
check_file_readable "Whisper model" "$WHISPER_MODEL_PATH"
check_file_readable "Piper voice model" "$PIPER_VOICE_PATH"

echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
