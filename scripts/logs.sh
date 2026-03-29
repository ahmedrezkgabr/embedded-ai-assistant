#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/tmp/ai-assistant-logs"
BACKEND_LOG="$LOG_DIR/backend.log"
LLAMA_LOG="$LOG_DIR/llama.log"
VERBOSE=0

if [ "${1:-}" = "--verbose" ]; then
  VERBOSE=1
fi

mkdir -p "$LOG_DIR"
touch "$BACKEND_LOG" "$LLAMA_LOG"

tail -f "$BACKEND_LOG" \
  | sed 's/^/\033[0;36m[backend]\033[0m /' &
BACKEND_PID=$!

if [ "$VERBOSE" -eq 1 ]; then
  tail -f "$LLAMA_LOG" \
    | sed 's/^/\033[0;33m[llama]  \033[0m /' &
else
  tail -f "$LLAMA_LOG" \
    | grep --line-buffered -v \
      -e "slot update_slots" \
      -e "slot launch_slot_" \
      -e "slot init_sampler" \
      -e "sched_reserve" \
      -e "load_tensors" \
      -e "print_info:" \
      -e "llama_model_loader" \
    | sed 's/^/\033[0;33m[llama]  \033[0m /' &
fi
LLAMA_PID=$!

cleanup() {
  kill "$BACKEND_PID" "$LLAMA_PID" 2>/dev/null || true
}

trap cleanup EXIT INT TERM
wait
