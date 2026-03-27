# Embedded AI Assistant

A fully local, end-to-end AI assistant for embedded Linux targets. The system runs all inference and media processing on-device with no cloud dependency at runtime.

## Core Components

- **LLM**: `llama.cpp` serving `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`
- **STT**: `whisper.cpp` with `tiny.en` model
- **TTS**: `Piper` with `en_US-lessac-low` voice
- **Backend**: Express.js API server
- **Frontend**: Vanilla HTML/CSS/JS web interface
- **Platform**: Yocto image for `qemux86-64` and Raspberry Pi 5

## Runtime Principle

No internet is required during runtime. Binaries and models are preinstalled into the image.
