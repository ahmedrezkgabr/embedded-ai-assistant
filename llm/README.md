# LLM Runtime

This subsystem uses `llama.cpp` with `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`.

## Model Choice

- 0.5B parameters, ~380 MB on disk
- Runs within constrained memory targets (QEMU 1 GB and Raspberry Pi 5)
- Typical throughput on Pi 5: ~4–8 tok/s
- Strong English instruction-following for this size class
- Apache 2.0 licensed model family

## Runtime Parameters

- Context length: 2048
- Threads: 2
- GPU layers: 0 (`-ngl 0`)
- Chat template: `qwen2`

Use `setup.sh` to clone/build llama.cpp and run the local HTTP server on port `11434`.

