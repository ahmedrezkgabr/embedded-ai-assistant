#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_DIR="${SCRIPT_DIR}/build/tmp/deploy/images/raspberrypi5"
IMAGE="${IMAGE_DIR}/ai-assistant-image-raspberrypi5.rootfs.wic.bz2"

if [ ! -f "$IMAGE" ]; then
  IMAGE="${IMAGE_DIR}/ai-assistant-image-raspberrypi5.wic.bz2"
fi

DEVICE="${1:-}"

if [ -z "$DEVICE" ]; then
  echo "Usage: $0 /dev/sdX"
  exit 1
fi

if [ ! -f "$IMAGE" ]; then
  echo "Image not found under ${IMAGE_DIR}. Build it first with bitbake ai-assistant-image."
  exit 1
fi

echo "Flashing $IMAGE to $DEVICE ..."
bzip2 -dc "$IMAGE" | sudo dd of="$DEVICE" bs=4M status=progress
sync
echo "Flash complete. Insert SD into Pi 5 and power on."
echo "Access UI at http://<pi5-ip>:3000"
