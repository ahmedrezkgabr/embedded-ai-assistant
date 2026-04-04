# Changelog

All notable changes to this project will be documented in this file.

Format based on Keep a Changelog.
Versioning follows Semantic Versioning.

## [Unreleased]

### Added
- Complete embedded Linux AI assistant system
- Express.js backend with LLM, STT, and TTS routes
- Web-based voice and text chat UI
- llama.cpp integration with Qwen2.5-0.5B-Q4_K_M
- whisper.cpp integration with ggml-tiny.en model
- Piper TTS integration with en_US-lessac-low voice
- Yocto Scarthgap meta-ai-assistant custom layer
- QEMU emulation target (qemux86-64)
- Raspberry Pi 5 target (aarch64)
- GitHub Actions CI pipeline (lint, unit test, build, integration, e2e-voice)
- scripts/setup.sh for one-command setup
- scripts/check.sh for preflight verification
- scripts/test.sh for 8-test end-to-end validation
- start.sh with LAN URL display and self-tests
- Production readiness plan (plan.md)

### Security
- CORS restricted to RFC-1918 private IP ranges
- Multer file size limit (10 MB) and WAV-only filter
- Stack traces suppressed in production mode

## [0.1.0] - 2024-XX-XX
Initial release — to be tagged when CI is fully green.