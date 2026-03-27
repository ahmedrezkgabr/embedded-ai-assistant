# Hardware Guide

## Audio Hardware Recommendations

### USB microphones tested/profiled

- Fifine K669B (USB condenser)
- Samson Go Mic (compact USB)
- Generic UAC1/UAC2 USB microphones

### Speaker options

- USB speaker/bar that enumerates as ALSA playback device
- 3.5mm output via supported DAC HAT
- I2S HAT with ALSA driver support

## ALSA Configuration

Example `/etc/asound.conf` to prefer USB audio devices:

```conf
pcm.!default {
  type asym
  playback.pcm "plughw:1,0"
  capture.pcm  "plughw:2,0"
}

ctl.!default {
  type hw
  card 1
}
```

Verify devices:

```bash
arecord -l
aplay -l
```

## Performance Benchmarks (Indicative)

| Service | QEMU qemux86-64 (1GB, 2 cores) | Raspberry Pi 5 |
|---|---:|---:|
| LLM (Qwen2.5-0.5B Q4_K_M) | ~2–4 tok/s | ~4–8 tok/s |
| STT (tiny.en, 5s audio) | ~3–6 s | ~1.5–3 s |
| TTS (short sentence) | near real-time | real-time |

## Memory Usage Breakdown (Approximate)

- Base OS + services: 220–350 MB
- Node backend + UI: 80–140 MB
- llama.cpp runtime + model mappings: 420–650 MB
- whisper-cli invocation peak: 120–220 MB (per request)
- piper invocation peak: 40–100 MB (per request)

These values vary with kernel config, allocator behavior, and concurrent requests.
