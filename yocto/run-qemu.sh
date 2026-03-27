#!/bin/bash
set -e

echo "Starting QEMU — open http://localhost:3000 in browser"
runqemu \
  qemux86-64 \
  ai-assistant-image \
  nographic \
  qemuparams="-m 1024 -smp 2" \
  slirp \
  hostfwd=tcp::3000-:3000 \
  hostfwd=tcp::11434-:11434 \
  hostfwd=tcp::2222-:22

# SSH: ssh -p 2222 root@localhost
