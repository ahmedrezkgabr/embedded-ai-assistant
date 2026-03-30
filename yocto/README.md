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

## Build prerequisites

Before running a Yocto image build, ensure these model files already exist in the project workspace:

- `llm/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`
- `stt/models/ggml-tiny.en.bin`
- `tts/models/en_US-lessac-low.onnx`
- `tts/models/en_US-lessac-low.onnx.json`

The backend recipe validates these files during `do_install` and fails early if any are missing.

