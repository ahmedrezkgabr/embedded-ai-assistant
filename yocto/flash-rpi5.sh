#!/bin/bash
set -euo pipefail

IMAGE="ai-assistant-image-raspberrypi5.wic.bz2"
DEVICE="${1:-}"

if [ -z "$DEVICE" ]; then
  echo "Usage: $0 /dev/sdX"
  exit 1
fi

echo "Flashing $IMAGE to $DEVICE ..."
bzip2 -dc "$IMAGE" | sudo dd of="$DEVICE" bs=4M status=progress
sync
echo "Flash complete. Insert SD into Pi 5 and power on."
echo "Access UI at http://<pi5-ip>:3000"
