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

## Quick start

### 1. Clone and set up
git clone <repo>
cd embedded-ai-assistant
bash scripts/setup.sh          # builds binaries, downloads models

### 2. Verify setup
bash scripts/check.sh          # prints PASS/FAIL for all 13 checks

### 3. Start the system
./start.sh                     # starts all services and prints URL

### 4. Access from any device
Open the URL printed by start.sh in any browser on your network.
Example: http://192.168.1.42:3000

### 5. Test the running system
bash scripts/test.sh           # runs 8 end-to-end tests

### 6. Stop the system
./stop.sh                      # or press Ctrl+C in the start.sh terminal

### Scripts reference
| Script               | Purpose                                    |
|----------------------|--------------------------------------------|
| scripts/setup.sh     | one-time build and model download          |
| scripts/check.sh     | preflight check, no services needed        |
| start.sh             | start all services, print LAN URL          |
| stop.sh              | stop all services                          |
| scripts/test.sh      | run 8 end-to-end tests against running sys |
| scripts/logs.sh      | tail all service logs with prefixes        |

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
