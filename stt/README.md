# STT (Whisper.cpp)

This subsystem uses `whisper.cpp` with `ggml-tiny.en.bin`.

## Why tiny.en

- ~75 MB model footprint
- ~39M parameters, optimized for English transcription
- Fast enough for near-real-time short utterances on Raspberry Pi 5
- Runs fully offline with no cloud dependency

## Execution Model

`whisper-cli` is invoked per request by the backend `sttService.js`.
There is no long-running daemon for STT in this architecture.

## Audio Format Constraint

Input must be WAV, 16 kHz, mono, 16-bit PCM. The frontend encoder and backend pipeline enforce this format.

