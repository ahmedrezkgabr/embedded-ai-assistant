#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for PORT in 3000 11434; do
  PIDS=$(lsof -ti ":$PORT" 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    echo "Killing PID(s) $PIDS on port $PORT"
    kill $PIDS 2>/dev/null || true
  else
    echo "Nothing running on port $PORT"
  fi
done

echo "All services stopped"
