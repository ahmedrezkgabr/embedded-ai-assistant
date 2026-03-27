# Yocto Integration

This directory contains the `meta-ai-assistant` layer and helper scripts for building a fully offline image for:

- `qemux86-64` (development)
- `raspberrypi5` (production)

## Contents

- Layer config (`meta-ai-assistant/conf/layer.conf`)
- Recipes for `llama.cpp`, `whisper.cpp`, `piper`, and backend integration
- Image recipe with Node.js, ALSA, and AI runtime packages
- Sample `local.conf` and `bblayers.conf` files

Use `setup.sh` to clone required Yocto layers (`poky`, `meta-openembedded`, `meta-raspberrypi`).

