# TTS (Piper)

This subsystem uses Piper with the `en_US-lessac-low` voice.

## Profile

- Small ONNX voice model (~12 MB)
- Real-time synthesis on Raspberry Pi 5 and QEMU x86_64 targets
- Natural-sounding output without GPU
- Output WAV sample rate: 22050 Hz

Use `setup.sh` to download the right Piper binary for `x86_64` or `aarch64`, fetch the voice model, and run a local synthesis test.
