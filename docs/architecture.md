# Architecture

## Runtime layers

1. Browser UI (`backend/public/*`) serves chat and voice controls.
2. Express backend (`backend/src/*`) provides REST + SSE orchestration.
3. Local AI engines:
   - `llama-server` for LLM on port `11434`
   - `whisper-cli` for STT subprocess execution
   - `piper` for TTS subprocess execution
4. Local model artifacts under `llm/models`, `stt/models`, `tts/models`.

## Request flow

- Text chat: UI -> `POST /api/llm/chat` -> llama `/v1/chat/completions` -> JSON reply.
- Streaming chat: UI -> `POST /api/llm/stream` -> SSE token stream from llama.
- STT: UI WAV upload -> `POST /api/voice/stt` -> whisper-cli -> transcript JSON.
- TTS: UI text -> `POST /api/voice/tts` -> piper -> WAV response.

## Port and path contract

- Backend API/UI: `3000`
- llama-server API: `11434`
- Canonical binaries:
  - `llm/llama.cpp/build/bin/llama-server`
  - `stt/whisper.cpp/build/bin/whisper-cli`
  - `tts/bin/piper`
- Canonical models:
  - `llm/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`
  - `stt/models/ggml-tiny.en.bin`
  - `tts/models/en_US-lessac-low.onnx` (+ `.json`)

## Deployment modes

- Local dev via `scripts/setup.sh`, `scripts/check.sh`, `start.sh`.
- Service deployment via `backend/deploy/install.sh` and systemd units.
- Yocto image via `yocto/meta-ai-assistant` recipes and `ai-assistant-image`.
