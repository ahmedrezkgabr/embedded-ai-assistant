# Embedded AI Assistant

A complete, end-to-end, locally hosted AI assistant for embedded Linux. At runtime, every service runs on-device with no internet dependency.

```txt
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Web UI (Vanilla HTML/CSS/JS)                     │
│  - Chat view, mic capture, WAV encoder, local playback     │
└──────────────────────────────┬──────────────────────────────┘
							   │ HTTP
┌──────────────────────────────▼──────────────────────────────┐
│  Layer 2: Express Backend                                  │
│  - /api/llm, /api/voice (stt/tts), SSE streaming           │
└──────────────┬───────────────────────┬──────────────────────┘
			   │                       │
┌──────────────▼─────────────┐ ┌──────▼───────────────────────┐
│ Layer 3A: llama.cpp server │ │ Layer 3B: subprocess workers │
│ - Qwen2.5-0.5B Q4_K_M GGUF │ │ - whisper-cli, piper         │
└──────────────┬──────────────┘ └──────────┬───────────────────┘
			   │                            │
┌──────────────▼────────────────────────────▼─────────────────┐
│  Layer 4: Local Models                                      │
│  - Qwen2.5 GGUF, tiny.en GGML, lessac-low ONNX             │
└──────────────┬───────────────────────────────────────────────┘
			   │
┌──────────────▼───────────────────────────────────────────────┐
│  Layer 5: Yocto Image + ALSA + Systemd                      │
│  - qemux86-64 dev target, Raspberry Pi 5 production         │
└──────────────────────────────────────────────────────────────┘
```

## Hardware Requirements

### Target A — QEMU (development)

- Machine: `qemux86-64`
- RAM: 1 GB
- CPU: 2 cores
- Storage: 2 GB image

### Target B — Raspberry Pi 5 (production)

- CPU: Cortex-A76, 4 cores @ 2.4 GHz (aarch64)
- RAM: 4 GB or 8 GB
- Storage: microSD or NVMe via HAT
- Audio: USB mic + USB speaker (or I2S HAT)

## Quick Start (Local Dev, no QEMU)

1. `bash llm/setup.sh`
2. `bash stt/setup.sh`
3. `bash tts/setup.sh`
4. `cd backend && cp .env.example .env && npm install`
5. `npm run dev`
6. Open `http://localhost:3000`

## Quick Start (QEMU)

1. `cd yocto && bash setup.sh`
2. `source poky/oe-init-build-env build`
3. Copy sample conf files and run: `bitbake ai-assistant-image`
4. `bash run-qemu.sh`
5. Open `http://localhost:3000`

## Quick Start (Raspberry Pi 5)

1. Build with `MACHINE=raspberrypi5`: `bitbake ai-assistant-image`
2. `bash flash-rpi5.sh /dev/sdX`
3. Boot Pi 5 and open `http://<pi5-ip>:3000`

## Runtime Guarantees

- No cloud APIs for LLM/STT/TTS
- No frontend frameworks or CDNs
- Runtime works offline with preinstalled binaries/models

## Documents

- `docs/api.md`
- `docs/hardware.md`
- `docs/voice-pipeline.md`
