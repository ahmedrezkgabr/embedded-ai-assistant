# Voice Pipeline (End-to-End)

The voice path remains fully local and offline:

1. Browser captures mic audio with `MediaRecorder` (`audio/webm;codecs=opus`)
2. Frontend decodes and resamples audio to WAV (16 kHz, mono, PCM16)
3. Browser uploads WAV to `POST /api/voice/stt`
4. Backend executes `whisper-cli` with `ggml-tiny.en.bin`
5. Transcript returns to browser
6. Browser sends transcript to `POST /api/llm/stream`
7. Backend forwards to `llama-server` hosting Qwen2.5-0.5B
8. Assistant response text is displayed incrementally (SSE)
9. Browser posts response text to `POST /api/voice/tts`
10. Backend executes `piper`, returns WAV, browser plays via `Audio()`

## Dataflow Summary

`Mic -> MediaRecorder -> WAV encode -> STT -> LLM -> TTS -> Speaker`

## Offline Guarantee

All inference binaries and model files are local. No cloud APIs are used at runtime.
