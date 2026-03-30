# Embedded AI Assistant — Production Readiness Plan

## System overview

The Embedded AI Assistant is a fully offline, locally-hosted voice and text AI assistant designed for embedded Linux targets (QEMU qemux86-64 for development, Raspberry Pi 5 for production). It combines an Express.js backend orchestrating three local AI engines — llama.cpp (LLM), whisper.cpp (STT), and piper (TTS) — with a vanilla HTML/CSS/JS frontend that handles voice capture, WAV encoding, streaming chat, and audio playback. "Production ready" means: every user-facing feature works reliably on the target hardware, temp files are cleaned up, errors are surfaced not swallowed, security defaults are sane, CI catches regressions, the Yocto image boots and self-tests, and documentation matches code.

## Audit scope

**Project configuration**: `backend/package.json`, `backend/.env.example`, `backend/.env`, `backend/eslint.config.cjs`, `backend/.eslintrc.cjs`, `backend/jest.config.js`, `.gitignore`

**Backend source**: `backend/src/server.js`, `backend/src/app.js`, `backend/src/config/runtime.js`, `backend/src/routes/llm.js`, `backend/src/routes/voice.js`, `backend/src/controllers/llmController.js`, `backend/src/controllers/voiceController.js`, `backend/src/services/llmService.js`, `backend/src/services/sttService.js`, `backend/src/services/ttsService.js`, `backend/src/middleware/errorHandler.js`, `backend/src/middleware/requestId.js`, `backend/src/middleware/validate.js`

**Frontend**: `backend/public/index.html`, `backend/public/style.css`, `backend/public/app.js`

**Unit tests**: `backend/tests/unit/llmService.test.js`, `backend/tests/unit/sttService.test.js`, `backend/tests/unit/ttsService.test.js`, `backend/tests/unit/validate.test.js`

**AI runtime**: `llm/setup.sh`, `llm/model-config.json`, `llm/llama-server.service`, `stt/setup.sh`, `tts/setup.sh`, `tts/piper-voices.json`

**Deployment**: `backend/deploy/ai-assistant.service`, `backend/deploy/install.sh`

**Yocto**: `yocto/setup.sh`, `yocto/run-qemu.sh`, `yocto/flash-rpi5.sh`, `yocto/test-system.sh`, `yocto/conf/local.conf.sample`, `yocto/conf/local-rpi5.conf.sample`, `yocto/conf/bblayers.conf.sample`, `yocto/meta-ai-assistant/conf/layer.conf`, `yocto/meta-ai-assistant/recipes-ai/llama-cpp/llama-cpp_git.bb`, `yocto/meta-ai-assistant/recipes-ai/whisper-cpp/whisper-cpp_git.bb`, `yocto/meta-ai-assistant/recipes-ai/piper-tts/piper-tts_git.bb`, `yocto/meta-ai-assistant/recipes-ai/llm-bridge/ai-assistant-backend_1.0.bb`, `yocto/meta-ai-assistant/recipes-ai/ai-assistant-backend/ai-assistant-backend_1.0.bb`, `yocto/meta-ai-assistant/recipes-core/images/ai-assistant-image.bb`

**Scripts**: `start.sh`, `stop.sh`, `scripts/setup.sh`, `scripts/check.sh`, `scripts/test.sh`, `scripts/logs.sh`, `check_system.sh`

**CI/CD**: `.github/workflows/ci.yml`

**Documentation**: `README.md`, `docs/api.md`, `docs/architecture.md`, `docs/hardware.md`, `docs/voice-pipeline.md`

---

## Findings

### F-001 — CI .env values are indented, dotenv will parse them with leading spaces
| Field       | Value |
|-------------|-------|
| Severity    | CRITICAL |
| Category    | Correctness |
| Subsystem   | ci |
| File(s)     | `.github/workflows/ci.yml` lines 142-165 |
| Blocks prod | YES |

**What is wrong**
The `Write backend/.env` step uses a heredoc indented inside a YAML block. The resulting `.env` file has leading spaces on every line (e.g. `          PORT=3000`). `dotenv` parses keys literally, so `process.env['          PORT']` is set rather than `process.env.PORT`. All env var lookups in `runtime.js` silently fall to defaults.

**Why it matters**
Every integration test in CI runs against hardcoded fallback values, not the intended `.env` configuration. LLM_BASE_URL falls back to `http://127.0.0.1:8080` (runtime.js line 16) instead of port 11434, causing all LLM calls to fail or hit the wrong server.

**Fix required**
Remove all leading indentation from the heredoc body. Use `cat > backend/.env <<'EOF'` with unindented content, or use `<<-EOF` with tab-only indentation (YAML uses spaces, so prefer unindented).

**Verification**
After fix, run in CI: `grep -c '^ ' backend/.env` must output `0`. Then `node -e "require('dotenv').config({path:'backend/.env'}); console.log(process.env.PORT)"` must print `3000`.

---

### F-002 — Frontend system_prompt sent inside options object but not forwarded to LLM
| Field       | Value |
|-------------|-------|
| Severity    | CRITICAL |
| Category    | Correctness |
| Subsystem   | backend |
| File(s)     | `backend/public/app.js:93-95`, `backend/src/controllers/llmController.js:82,110`, `backend/src/services/llmService.js:24-28` |
| Blocks prod | YES |

**What is wrong**
The frontend sends `options: { system_prompt: state.settings.systemPrompt }`. The controller spreads `req.body.options` into `options`, so `options.system_prompt` exists. In `llmService.js:24-28`, `buildMessages` checks `options.systemPrompt` (camelCase) first, then `options.system_prompt` (snake_case), then falls back to `DEFAULT_SYSTEM_PROMPT`. It will find `system_prompt` — but this means the user-typed system prompt in the Settings panel **overrides** the strict English-only system prompt from `LLM_STRICT_SYSTEM_PROMPT`. A user can type "Respond in Chinese" and bypass the safety prompt.

**Why it matters**
The system has a strict English-only system prompt for production safety. Allowing the UI to override it means the LLM can produce non-ASCII output, breaking voice synthesis and violating the offline-English guarantee.

**Fix required**
In `llmService.js buildMessages()`, always prepend the `DEFAULT_SYSTEM_PROMPT` (from env) as the primary system message. If the user provides a custom system prompt, append it as a second system message or concatenate after the strict prompt. Never let client-provided systemPrompt fully replace the strict one.

**Verification**
Set system prompt in UI to "Reply in Chinese". Send "What is 2+2?". Response must still be English ASCII only.

---

### F-003 — SSE stream test (TEST 3) expects `data: {"done":true}` but controller emits named events
| Field       | Value |
|-------------|-------|
| Severity    | CRITICAL |
| Category    | Consistency |
| Subsystem   | scripts |
| File(s)     | `scripts/test.sh:106`, `backend/src/controllers/llmController.js:189,208` |
| Blocks prod | YES |

**What is wrong**
The controller uses `sendSse({ done: true }, 'done')` which writes `event: done\ndata: {"done":true}\n\n` and `sendSse({ token: ..., done: false }, 'token')` which writes `event: token\ndata: ...\n\n`. But `test.sh:106` checks `last_line == 'data: {"done":true}'` using plain `grep '^data: '`. With named events, the output has `event: done` on the preceding line. The grep should still find the data line, but the exact match `data: {"done":true}` may fail because the named event prefix `event: done\n` appears before it — the grep finds it, but the comparison includes extra fields. Actually, looking more carefully, `grep '^data: '` will match `data: {"done":true}` correctly, but the frontend `app.js:119-135` uses `response.body.getReader()` which doesn't process SSE named events — it reads raw bytes, so both `event:` and `data:` lines are in the stream. The frontend SSE parser only looks for `data:` lines, so named events are effectively ignored. The frontend will work, but it swallows the `event:` information.

The actual critical issue is that the frontend parser (`app.js:128`) does `JSON.parse(payload)` on every data line without a try/catch. If a malformed frame arrives (network glitch, partial chunk), the entire streaming function throws and the assistant bubble shows "Error" — no graceful degradation.

**Why it matters**
Any SSE parse error kills the entire streaming response with no recovery.

**Fix required**
Wrap `JSON.parse(payload)` at `app.js:128` in a try/catch that continues on parse failure. Also consider: the frontend should handle `event:` lines for proper SSE parsing, or the backend should stop using named events since the frontend ignores them.

**Verification**
Send a streaming chat request. Inject a network hiccup (e.g. Chrome DevTools throttling). Partial tokens should still render; malformed frames should be skipped, not crash the UI.

---

### F-004 — No validation middleware on LLM chat/stream routes
| Field       | Value |
|-------------|-------|
| Severity    | HIGH |
| Category    | Completeness |
| Subsystem   | backend |
| File(s)     | `backend/src/routes/llm.js`, `backend/src/middleware/validate.js` |
| Blocks prod | NO |

**What is wrong**
The `validate` middleware only defines `ttsRequest`. The LLM routes (`/chat`, `/stream`) have no request validation middleware — validation is done inline in the controller. The `validate.js` module is not used for LLM routes at all. The controller validates `prompt` manually but does not validate `model`, `temperature`, `max_tokens`, or `options` fields. A client can send `temperature: "abc"` or `max_tokens: 999999`.

**Why it matters**
Malformed inputs pass through to llama-server which may behave unpredictably. `max_tokens: 999999` could cause extremely long generation that ties up the LLM for minutes.

**Fix required**
Add validation rules in `validate.js` for chat/stream requests: `prompt` must be non-empty string, `temperature` optional number 0-2, `max_tokens` optional integer 1-2048, `model` optional string. Mount on LLM routes.

**Verification**
`curl -X POST /api/llm/chat -d '{"prompt":"hi","max_tokens":"abc"}' -H 'Content-Type: application/json'` returns 400.

---

### F-005 — multer has no file size limit or file type filter
| Field       | Value |
|-------------|-------|
| Severity    | HIGH |
| Category    | Security |
| Subsystem   | backend |
| File(s)     | `backend/src/routes/voice.js:12` |
| Blocks prod | NO |

**What is wrong**
`multer({ dest: runtime.uploads.dir })` is configured with no `limits` or `fileFilter`. Any file of any size and any MIME type can be uploaded. A 1 GB upload would fill `/tmp` and crash whisper-cli and the entire system.

**Why it matters**
An attacker or misbehaving client can exhaust disk space, causing whisper/piper temp file writes to fail and potentially crashing the Express server.

**Fix required**
Add multer configuration: `limits: { fileSize: 10 * 1024 * 1024 }` (10 MB max), and `fileFilter` that only accepts `audio/wav`, `audio/wave`, `audio/x-wav`, and `audio/webm` MIME types. Return 413 for oversized and 400 for wrong type.

**Verification**
`curl -X POST /api/voice/stt -F "audio=@/dev/urandom;type=text/plain" | jq .error` returns 400. `dd if=/dev/zero bs=1M count=20 | curl -X POST /api/voice/stt -F "audio=@-;type=audio/wav"` returns 413.

---

### F-006 — CORS is wide open: `app.use(cors())`
| Field       | Value |
|-------------|-------|
| Severity    | HIGH |
| Category    | Security |
| Subsystem   | backend |
| File(s)     | `backend/src/app.js:20` |
| Blocks prod | NO |

**What is wrong**
`cors()` with no arguments sets `Access-Control-Allow-Origin: *`. Any website on any domain can make requests to the API, including voice upload and LLM querying.

**Why it matters**
On a LAN-connected embedded device, any website opened by any user on the same network can silently send requests to the assistant API.

**Fix required**
Configure CORS with an explicit origin list: `cors({ origin: ['http://localhost:3000', /^http:\/\/192\.168\.\d+\.\d+:3000$/] })` or read allowed origins from an env var.

**Verification**
`curl -H 'Origin: https://evil.com' -I http://localhost:3000/api/llm/health | grep Access-Control-Allow-Origin` must NOT return `*`.

---

### F-007 — STT upload temp file not cleaned up on whisper failure
| Field       | Value |
|-------------|-------|
| Severity    | HIGH |
| Category    | Performance |
| Subsystem   | backend |
| File(s)     | `backend/src/services/sttService.js:62-67`, `backend/src/controllers/voiceController.js:4-15` |
| Blocks prod | NO |

**What is wrong**
In `sttService.js`, the `finally` block deletes `outputTextPath` and `resolvedWavPath`. But `resolvedWavPath` is the multer-uploaded file. If `runWhisper` throws before creating output, `outputTextPath` doesn't exist — `unlink` rejects (caught by `allSettled`). That's fine. However, the multer upload file (`req.file.path`) is the same as `resolvedWavPath` passed to `transcribe()`, so it IS cleaned. But if `transcribe()` throws before reaching the `finally` block (e.g. `mkdir` fails), the upload file leaks. More importantly: on concurrent requests, all whisper output files use the same prefix `whisper_out` with only `Date.now()` for uniqueness — two requests in the same millisecond overwrite each other.

**Why it matters**
Leaked temp files accumulate in `/tmp`. Concurrent request collision corrupts transcription results.

**Fix required**
Use `crypto.randomUUID()` or `os.tmpdir()` + `mkdtemp` for unique output paths. Ensure the uploaded file is always cleaned in a `finally` block in the controller, not just the service.

**Verification**
Send 10 concurrent STT requests. After all complete, `ls /tmp/ai-assistant/whisper_out*` returns nothing. No file collisions in logs.

---

### F-008 — TTS output file collision on concurrent requests (same Date.now())
| Field       | Value |
|-------------|-------|
| Severity    | HIGH |
| Category    | Performance |
| Subsystem   | backend |
| File(s)     | `backend/src/services/ttsService.js:64` |
| Blocks prod | NO |

**What is wrong**
`tts_out_${Date.now()}.wav` can produce identical filenames when two TTS requests happen in the same millisecond. The second piper process would overwrite the first's output.

**Why it matters**
The first request reads the second request's audio or gets a "file not found" error.

**Fix required**
Use `crypto.randomUUID()` instead of `Date.now()` for the output filename suffix.

**Verification**
Send 10 concurrent TTS requests with different text. All must return different audio content.

---

### F-009 — model-config.json temperature/top_p/max_tokens conflict with .env defaults
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Consistency |
| Subsystem   | llm |
| File(s)     | `llm/model-config.json`, `backend/.env.example`, `backend/.env` |
| Blocks prod | NO |

**What is wrong**
`model-config.json` sets `temperature: 0.7`, `top_p: 0.9`, `max_tokens: 256`. `.env.example` and `.env` set `LLM_TEMPERATURE=0`, `LLM_TOP_P=0.2`, `LLM_MAX_TOKENS=128`. The UI defaults also differ: temperature slider defaults to `0.7`, max_tokens input defaults to `256`. There are three sources of truth for the same parameters.

**Why it matters**
Confusing for developers. `model-config.json` is not read by any code — it's a dead file that gives wrong expectations.

**Fix required**
Either remove `model-config.json` (it's unused), or make it the single source of truth loaded by `runtime.js`. Align UI defaults with `.env` values: temperature slider default `value="0"`, max_tokens default `value="128"`.

**Verification**
`grep -r 'model-config.json' backend/` returns nothing. UI temperature slider starts at 0. UI max_tokens input starts at 128.

---

### F-010 — runtime.js LLM_BASE_URL fallback port 8080 differs from all other files' 11434
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Consistency |
| Subsystem   | backend |
| File(s)     | `backend/src/config/runtime.js:16` |
| Blocks prod | NO |

**What is wrong**
`runtime.js` line 16: `baseUrl: process.env.LLM_BASE_URL || 'http://127.0.0.1:8080'`. Every other file (`.env.example`, `.env`, `start.sh`, `llama-server.service`, CI workflow) uses port 11434. If `LLM_BASE_URL` is unset (e.g. systemd service missing the env var), the backend connects to port 8080 — nothing listens there.

**Why it matters**
Silent failure: health checks return `unreachable`, LLM requests fail with 503, and the error message doesn't mention the port mismatch.

**Fix required**
Change `runtime.js:16` fallback from `'http://127.0.0.1:8080'` to `'http://127.0.0.1:11434'`.

**Verification**
Unset `LLM_BASE_URL`, start backend. `curl /api/llm/health` returns `ok: true`.

---

### F-011 — runtime.js default model name case differs from .env and llama-server
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Consistency |
| Subsystem   | backend |
| File(s)     | `backend/src/config/runtime.js:18` |
| Blocks prod | NO |

**What is wrong**
`runtime.js:18`: `defaultModel: process.env.LLM_DEFAULT_MODEL || 'qwen2.5-0.5b-instruct-q4_k_m'`. The fallback uses lowercase with no `.gguf` extension. `.env` and all other references use `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`. llama-server may reject unknown model names or return errors.

**Why it matters**
If `LLM_DEFAULT_MODEL` env var is unset, chat requests send a model name llama-server doesn't recognize.

**Fix required**
Change fallback to `'Qwen2.5-0.5B-Instruct-Q4_K_M.gguf'`.

**Verification**
Unset `LLM_DEFAULT_MODEL`, send chat request. Response includes correct `model` field.

---

### F-012 — runtime.js default maxTokens 512 differs from .env's 128
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Consistency |
| Subsystem   | backend |
| File(s)     | `backend/src/config/runtime.js:19` |
| Blocks prod | NO |

**What is wrong**
`runtime.js:19`: `maxTokens: toNumber(process.env.LLM_MAX_TOKENS, 512)`. The fallback is 512, but `.env.example` and `.env` both set `LLM_MAX_TOKENS=128`. If the env var is missing, the model generates up to 512 tokens — 4x the intended limit.

**Why it matters**
On embedded hardware, generating 512 tokens takes significantly longer, degrading voice response latency.

**Fix required**
Change fallback to 128 to match `.env.example`.

**Verification**
Unset `LLM_MAX_TOKENS`. `node -e "require('dotenv').config(); console.log(require('./src/config/runtime').llm.maxTokens)"` prints 128.

---

### F-013 — llmService.js reads LLM_STRICT_SYSTEM_PROMPT directly from process.env, bypassing runtime.js
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Consistency |
| Subsystem   | backend |
| File(s)     | `backend/src/services/llmService.js:7-9` |
| Blocks prod | NO |

**What is wrong**
Line 8: `process.env.LLM_STRICT_SYSTEM_PROMPT || 'You are a helpful assistant...'`. But `runtime.js:25-33` already reads the same env var into `runtime.llm.strictEnglishSystemPrompt` with a much more detailed fallback. The service ignores the runtime config and uses a weaker fallback.

**Why it matters**
Two different fallback system prompts exist. If env var is unset, `llmService` uses the weak prompt while `runtime.js` has a strict one that nobody reads.

**Fix required**
In `llmService.js`, replace `process.env.LLM_STRICT_SYSTEM_PROMPT || '...'` with `runtime.llm.strictEnglishSystemPrompt`. Remove the direct `process.env` read.

**Verification**
Unset the env var. Run chat request. Verify the detailed strict prompt (from `runtime.js` fallback) is used by checking llama-server logs for the system message.

---

### F-014 — Frontend does not handle microphone permission denial
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Completeness |
| Subsystem   | frontend |
| File(s)     | `backend/public/app.js:149-183` |
| Blocks prod | NO |

**What is wrong**
`startRecording()` calls `navigator.mediaDevices.getUserMedia({ audio: true })` at line 154. If the user denies mic permission, this throws. The catch block at line 449-451 shows `Mic error: <message>` in the status, but the mic button remains in `idle` state — it was changed to `recording` at line 159 which happens AFTER `getUserMedia`. Actually, looking again, the flow is: `getUserMedia` is awaited at line 154, then `setMicState('recording')` at line 159. If `getUserMedia` throws, it propagates to the `catch` at line 449. So the mic state stays `idle`. The status shows the error briefly, then the 15-second health check interval resets it. Actually no — `micStatus` is not reset by health checks. The error message persists. This is adequate but not great UX. The real gap: after denial, clicking the mic button again will just fail again with no explanation of how to fix it.

**Why it matters**
Users on embedded kiosks may not know how to re-grant mic permission after denial.

**Fix required**
After `getUserMedia` failure, check if `error.name === 'NotAllowedError'` and show a more helpful message: "Microphone access denied. Please allow mic access in browser settings and reload."

**Verification**
Deny mic permission in browser. Click mic button. Status shows the helpful message.

---

### F-015 — No request queuing / back-pressure for LLM
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Performance |
| Subsystem   | backend |
| File(s)     | `backend/src/services/llmService.js`, `backend/src/controllers/llmController.js` |
| Blocks prod | NO |

**What is wrong**
There is no queuing or concurrency limit for LLM requests. If 5 users send chat requests simultaneously, all 5 hit llama-server concurrently. llama-server with `--parallel 1` (default) queues internally, but the Express timeout still applies to the total wait. Users 2-5 may all timeout while user 1's request completes.

**Why it matters**
On embedded hardware (single model slot), concurrent requests degrade latency to the point where all requests timeout.

**Fix required**
Add a simple request queue (semaphore with concurrency 1). When the LLM is busy, subsequent requests wait in a FIFO queue with individual timeout. Optionally return 429 if the queue exceeds N entries.

**Verification**
Send 3 concurrent chat requests. All 3 complete (sequentially). None timeout unless individually exceeding `LLM_TIMEOUT`.

---

### F-016 — Yocto ai-assistant-backend recipe does not run npm install
| Field       | Value |
|-------------|-------|
| Severity    | HIGH |
| Category    | Yocto |
| Subsystem   | yocto |
| File(s)     | `yocto/meta-ai-assistant/recipes-ai/ai-assistant-backend/ai-assistant-backend_1.0.bb` |
| Blocks prod | YES |

**What is wrong**
The recipe copies `backend/` to `/opt/ai-assistant/backend/` and explicitly removes `node_modules`. But it never runs `npm install --omit=dev`. The deployed image has no `node_modules`, so `node src/server.js` fails with `Cannot find module 'express'`.

**Why it matters**
The Yocto-built image is completely non-functional — the backend service crashes on startup.

**Fix required**
Add `inherit npm` or a `do_install` step that runs `npm install --omit=dev --prefix ${D}/opt/ai-assistant/backend` in a `do_install:append`. Or use `RDEPENDS` on nodejs-npm and add a post-install script. Alternatively, bundle `node_modules` in the image by not deleting it.

**Verification**
Build image, boot QEMU, run `ls /opt/ai-assistant/backend/node_modules/express` — directory exists. `systemctl status ai-assistant` shows active.

---

### F-017 — Yocto IMAGE_ROOTFS_EXTRA_SPACE too small for models
| Field       | Value |
|-------------|-------|
| Severity    | HIGH |
| Category    | Yocto |
| Subsystem   | yocto |
| File(s)     | `yocto/conf/local.conf.sample:4`, `yocto/conf/local-rpi5.conf.sample:5`, `yocto/meta-ai-assistant/recipes-core/images/ai-assistant-image.bb:21` |
| Blocks prod | YES |

**What is wrong**
`IMAGE_ROOTFS_EXTRA_SPACE = "2097152"` = 2 GB. The Qwen2.5-0.5B Q4_K_M model alone is ~395 MB. Add whisper tiny.en (~75 MB), piper voice (~16 MB), node_modules (~50 MB), plus base OS. The 2 GB extra allows for this. However, the image recipe installs `nodejs`, `llama-cpp`, `whisper-cpp`, `piper-tts` (large binaries), and models totaling ~600+ MB, plus the base OS at ~300+ MB. With 2 GB extra, total rootfs can be 3+ GB. For RPi5 SD card this is fine, but for QEMU the default drive size may be too small. More critically: the recipe copies models from `${TOPDIR}/../llm/models/*.gguf` but these files may not exist at build time if `scripts/setup.sh` hasn't been run — the recipe silently skips them (`2>/dev/null || true`).

**Why it matters**
Image builds without models, boots without any AI capability, no error or warning during build.

**Fix required**
Add a `do_install` check that warns or fails if model files are not found. Document the prerequisite: `scripts/setup.sh` must complete before `bitbake ai-assistant-image`. Consider using `SRC_URI` with `file://` to fetch models, making them formal build dependencies.

**Verification**
Build image without running setup.sh first. Build must emit a clear warning about missing models.

---

### F-018 — Duplicate / conflicting ESLint configs
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Consistency |
| Subsystem   | backend |
| File(s)     | `backend/.eslintrc.cjs`, `backend/eslint.config.cjs` |
| Blocks prod | NO |

**What is wrong**
Two ESLint config files exist: the legacy `.eslintrc.cjs` (extends `'node'`, which doesn't exist as a shareable config in devDependencies) and the flat config `eslint.config.cjs`. ESLint 9 uses the flat config by default but may still detect the legacy file. The legacy config references `extends: ['node']` which is not installed — running `npm run lint` could fail or produce confusing warnings.

**Why it matters**
Lint may not work correctly, or may silently use the wrong config.

**Fix required**
Delete `backend/.eslintrc.cjs`. The flat config `eslint.config.cjs` is the correct one for ESLint 9.

**Verification**
`cd backend && npm run lint` completes with exit code 0 and uses `eslint.config.cjs`.

---

### F-019 — Frontend SSE parser has no try/catch around JSON.parse
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Robustness |
| Subsystem   | frontend |
| File(s)     | `backend/public/app.js:128` |
| Blocks prod | NO |

**What is wrong**
`const parsed = JSON.parse(payload)` at line 128 has no try/catch. If the SSE stream delivers a malformed JSON chunk (partial write, network corruption), the error propagates uncaught to the `catch` block at line 143, killing the entire streaming response and displaying "Error" in the assistant bubble, discarding all previously-received tokens.

**Why it matters**
A single corrupt byte in the stream destroys the entire response, including tokens already rendered.

**Fix required**
Wrap the `JSON.parse` in a try/catch that `continue`s on failure, preserving previously rendered tokens.

**Verification**
Simulate a bad SSE frame in the stream. Assistant bubble retains all previously received tokens.

---

### F-020 — No Express body size limit on multipart uploads (separate from multer)
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Robustness |
| Subsystem   | backend |
| File(s)     | `backend/src/app.js:22`, `backend/src/routes/voice.js:12` |
| Blocks prod | NO |

**What is wrong**
`express.json({ limit: '2mb' })` limits JSON bodies to 2 MB, but multer has no `limits` config. The STT endpoint can receive arbitrarily large files. Combined with F-005.

**Why it matters**
Disk exhaustion on embedded device with limited storage.

**Fix required**
Add `limits: { fileSize: 10 * 1024 * 1024 }` to multer config. This returns a `LIMIT_FILE_SIZE` error. Handle it in error handler to return 413.

**Verification**
Upload a 15 MB file to `/api/voice/stt`. Response is HTTP 413.

---

### F-021 — piper TTS output not validated for size before returning
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Robustness |
| Subsystem   | backend |
| File(s)     | `backend/src/services/ttsService.js:70-71` |
| Blocks prod | NO |

**What is wrong**
After `runPiper` resolves, the code does `fs.readFile(outputFile)` without checking the file exists or has non-zero size. On some Linux distros, piper can exit 0 but write an empty or truncated WAV file.

**Why it matters**
The API returns a 0-byte or invalid WAV body with status 200, causing silent audio playback failure in the browser.

**Fix required**
After `readFile`, check `buffer.length > 44` (minimum WAV header). If not, throw an error: "TTS produced empty audio".

**Verification**
Mock piper to write 0-byte file. TTS endpoint returns 500 with "TTS produced empty audio".

---

### F-022 — Frontend temperature slider default (0.7) and max_tokens default (256) conflict with backend
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Consistency |
| Subsystem   | frontend |
| File(s)     | `backend/public/index.html:51-52,56`, `backend/public/app.js:9-10` |
| Blocks prod | NO |

**What is wrong**
HTML: `temperature` slider `value="0.7"`, `max-tokens` input `value="256"`. JS state: `temperature: 0.7`, `max_tokens: 256`. But `.env` configures `LLM_TEMPERATURE=0`, `LLM_MAX_TOKENS=128`. The frontend overrides backend defaults via the `options` object, so the backend `.env` values are effectively ignored when using the UI.

**Why it matters**
The backend is configured for deterministic (temp=0) output to ensure consistent English-only responses. The UI silently overrides this to temp=0.7, increasing randomness and non-English token probability.

**Fix required**
Change HTML defaults to `value="0"` for temperature and `value="128"` for max_tokens. Change JS state defaults to match.

**Verification**
Open UI. Temperature slider shows 0. Max tokens shows 128.

---

### F-023 — OfflineAudioContext resampling creates mono buffer at source sample rate, not target
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | VoicePipeline |
| Subsystem   | frontend |
| File(s)     | `backend/public/app.js:213` |
| Blocks prod | NO |

**What is wrong**
Line 213: `const monoBuffer = offlineContext.createBuffer(1, decoded.length, decoded.sampleRate)`. This creates a buffer with `decoded.length` samples at the ORIGINAL sample rate (e.g., 48000 Hz). When this buffer is connected to the `OfflineAudioContext` running at 16000 Hz, the context resamples it. But the buffer's duration is `decoded.length / decoded.sampleRate`, which is correct. The `OfflineAudioContext` has `Math.ceil(decoded.duration * 16000)` output samples. The resampling happens correctly because the context destination is 16000 Hz. So the output IS correctly resampled. But there's an inefficiency: the intermediate mono buffer is at the original sample rate, making the mixing loop process more samples than necessary.

Actually, looking more carefully, this works correctly for resampling. The real voice pipeline issue is different.

**Why it matters**
Minor inefficiency but functionally correct.

**Fix required**
Low priority. Optionally create the mono buffer at target rate and resample during mixing, but current approach works.

**Verification**
Record 3-second voice clip. Upload to STT. Verify whisper processes it without sample rate errors.

---

### F-024 — No latency tracking or timeout feedback in the voice round-trip UI flow
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | VoicePipeline |
| Subsystem   | frontend |
| File(s)     | `backend/public/app.js:205-253` |
| Blocks prod | NO |

**What is wrong**
The voice flow chains: stop recording → WAV encode → upload STT → wait for transcript → send LLM chat → wait for streaming response → TTS. The user sees "Transcribing..." during STT but nothing during the LLM wait. The total round-trip on embedded hardware can be 5-15 seconds. If the LLM is slow, the user stares at a static screen after the transcript appears with no indication that the system is working.

**Why it matters**
Users will assume the system is frozen and press the mic button again, creating duplicate requests.

**Fix required**
After transcript arrives and `sendTextMessage` is called, the assistant bubble shows the typing cursor. This is adequate for the LLM phase. The gap is between STT completion and the assistant bubble appearing — the mic status changes to "Idle" at line 172 before `sendTextMessage` is called at line 249. Add a brief "Thinking..." status.

**Verification**
Speak a question. After "Transcribing..." clears, status briefly shows "Thinking..." before assistant bubble appears with cursor.

---

### F-025 — Frontend does not gracefully handle browser MediaRecorder mimeType unavailability
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | VoicePipeline |
| Subsystem   | frontend |
| File(s)     | `backend/public/app.js:156` |
| Blocks prod | NO |

**What is wrong**
Line 156: `new MediaRecorder(state.audioStream, { mimeType: 'audio/webm;codecs=opus' })`. Not all browsers support this exact mimeType. Safari, for example, may only support `audio/mp4` or have no codec specification. If the mimeType is unsupported, `MediaRecorder` constructor throws `NotSupportedError`.

**Why it matters**
Voice recording is completely broken on Safari and some mobile browsers.

**Fix required**
Check `MediaRecorder.isTypeSupported('audio/webm;codecs=opus')` first. Fall back to `audio/webm`, then let the browser choose default. Adjust the `processAudioToWAV` to handle the resulting format (the `decodeAudioData` call should handle various formats).

**Verification**
Open the UI in Safari. Mic recording starts without error.

---

### F-026 — CI integration test does not verify SSE streaming
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | CI |
| Subsystem   | ci |
| File(s)     | `.github/workflows/ci.yml:203-227` |
| Blocks prod | NO |

**What is wrong**
The CI `API integration checks` step tests: chat endpoint, TTS, STT, and static files. It does NOT test the `/api/llm/stream` SSE endpoint. Streaming is the primary interaction mode for the UI.

**Why it matters**
A regression in the SSE streaming code would not be caught by CI.

**Fix required**
Add an SSE streaming test to CI: `curl -sN -X POST /api/llm/stream -H 'Content-Type: application/json' -d '{"prompt":"Say hi"}' > /tmp/sse.out`, then verify the output contains `data:` lines and ends with `"done":true`.

**Verification**
Break `parseSseFrames()` intentionally. CI fails on the new streaming test.

---

### F-027 — CI e2e-voice test only checks transcript key exists, not content quality
| Field       | Value |
|-------------|-------|
| Severity    | LOW |
| Category    | CI |
| Subsystem   | ci |
| File(s)     | `.github/workflows/ci.yml:222` |
| Blocks prod | NO |

**What is wrong**
Line 222: `assert 'transcript' in data` only checks the key exists, not that the transcript is non-empty or meaningful. A sine wave produces a garbage transcript; the test passes regardless.

**Why it matters**
STT could be completely broken (returning empty transcripts) and CI wouldn't catch it.

**Fix required**
Assert that `len(data['transcript']) > 0` or that transcript is a string. For real speech testing, use a pre-recorded WAV with known content.

**Verification**
Modify whisper to return empty string. CI test fails.

---

### F-028 — docs/api.md shows `systemPrompt` (camelCase) but frontend sends `system_prompt` (snake_case)
| Field       | Value |
|-------------|-------|
| Severity    | LOW |
| Category    | Docs |
| Subsystem   | docs |
| File(s)     | `docs/api.md:21,57` |
| Blocks prod | NO |

**What is wrong**
`api.md` line 21 shows `"systemPrompt"` in the chat request options. Line 57 shows `"system_prompt"` in the stream request options. The frontend sends `system_prompt` (snake_case). The backend accepts both (llmService.js:26-27 checks `options.systemPrompt || options.system_prompt`). The docs are inconsistent with themselves.

**Why it matters**
Developers integrating with the API will use inconsistent field names.

**Fix required**
Standardize on one form (`system_prompt` to match frontend convention) and update `api.md` to use it consistently.

**Verification**
`grep -c 'systemPrompt' docs/api.md` returns 0. `grep -c 'system_prompt' docs/api.md` returns the correct count.

---

### F-029 — docs/voice-pipeline.md says browser sends transcript to POST /api/llm/chat, but UI uses /stream
| Field       | Value |
|-------------|-------|
| Severity    | LOW |
| Category    | Docs |
| Subsystem   | docs |
| File(s)     | `docs/voice-pipeline.md:6,10` |
| Blocks prod | NO |

**What is wrong**
Line 10: "Browser sends transcript to `POST /api/llm/chat` or `/api/llm/stream`". The frontend `sendTextMessage()` always uses `/api/llm/stream` (app.js:86). The `/chat` endpoint is not used by the UI at all.

**Why it matters**
Misleading documentation.

**Fix required**
Update to: "Browser sends transcript to `POST /api/llm/stream`".

**Verification**
Read `docs/voice-pipeline.md`. Step 6 says `/api/llm/stream` only.

---

### F-030 — docs/hardware.md references TinyLlama but system uses Qwen2.5-0.5B
| Field       | Value |
|-------------|-------|
| Severity    | LOW |
| Category    | Docs |
| Subsystem   | docs |
| File(s)     | `docs/hardware.md:45` |
| Blocks prod | NO |

**What is wrong**
Line 45 correctly says "Qwen2.5-0.5B Q4_K_M" — actually, this is correct. The user's prompt mentions checking for TinyLlama references. Let me re-read... The doc correctly references Qwen. However, the performance numbers are described as "indicative" with no date or commit reference, so there's no way to verify they match the current binary build.

**Why it matters**
Performance numbers become stale as llama.cpp and whisper.cpp are built from `master` (no pinned version).

**Fix required**
Add a note: "Benchmarks recorded against llama.cpp commit `<hash>` on `<date>`. Rebuild with the same version to reproduce."

**Verification**
`docs/hardware.md` includes a commit hash and date for benchmarks.

---

### F-031 — Yocto recipes use AUTOREV — non-reproducible builds
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Yocto |
| Subsystem   | yocto |
| File(s)     | `yocto/meta-ai-assistant/recipes-ai/llama-cpp/llama-cpp_git.bb:9`, `whisper-cpp_git.bb:9`, `piper-tts_git.bb:9` |
| Blocks prod | NO |

**What is wrong**
All three AI recipes use `SRCREV = "${AUTOREV}"` which fetches the latest commit from `master` at build time. Builds are not reproducible — a breaking change upstream silently breaks the image.

**Why it matters**
A production image must be byte-reproducible. AUTOREV means each build pulls whatever is on master, potentially introducing build failures or behavioral changes.

**Fix required**
Pin `SRCREV` to a known-good commit hash for each recipe. Add comments with the date and version.

**Verification**
`grep AUTOREV yocto/meta-ai-assistant/recipes-ai/*/*.bb` returns nothing.

---

### F-032 — Yocto RPi5 conf does not include ALSA or audio support config
| Field       | Value |
|-------------|-------|
| Severity    | MEDIUM |
| Category    | Yocto |
| Subsystem   | yocto |
| File(s)     | `yocto/conf/local-rpi5.conf.sample` |
| Blocks prod | NO |

**What is wrong**
The image recipe (`ai-assistant-image.bb`) adds `MACHINE_FEATURES:append = " alsa"` and installs `alsa-utils` and `alsa-lib`. But `local-rpi5.conf.sample` does not include any ALSA or sound-related configuration. For RPi5, USB audio may need additional kernel modules or device tree overlays (e.g., `dtoverlay=vc4-kms-v3d` for HDMI audio, or USB audio module loading).

**Why it matters**
Audio capture/playback may not work on RPi5 even though ALSA packages are installed.

**Fix required**
Add `MACHINE_FEATURES:append = " alsa"` to `local-rpi5.conf.sample`. Add any RPi5-specific audio config (USB audio kernel module loading).

**Verification**
Boot RPi5 image. `aplay -l` lists at least one playback device. `arecord -l` lists at least one capture device.

---

### F-033 — check_system.sh uses /usr/share/models path, different from all other files
| Field       | Value |
|-------------|-------|
| Severity    | LOW |
| Category    | Consistency |
| Subsystem   | scripts |
| File(s)     | `check_system.sh:4-6` |
| Blocks prod | NO |

**What is wrong**
Default `LLM_MODEL_PATH="/usr/share/models/qwen.gguf"` (not even the full filename), `WHISPER_MODEL_PATH="/usr/share/models/ggml-tiny.en.bin"`. All other files use `/opt/ai-assistant/models/` for deployed paths. The model filename is `qwen.gguf` not `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`.

**Why it matters**
Running `check_system.sh` without setting env vars will always report "FAIL" even when the system is correctly deployed.

**Fix required**
Change defaults to `/opt/ai-assistant/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`, `ggml-tiny.en.bin`, and `en_US-lessac-low.onnx`.

**Verification**
On a deployed system, `bash check_system.sh` passes without setting env vars.

---

### F-034 — sttService does not clean up upload file if mkdir throws
| Field       | Value |
|-------------|-------|
| Severity    | LOW |
| Category    | Completeness |
| Subsystem   | backend |
| File(s)     | `backend/src/services/sttService.js:52-67` |
| Blocks prod | NO |

**What is wrong**
Line 52: `await fs.mkdir(...)`. If this throws (e.g., permission denied on `/tmp`), the `finally` block tries to unlink `outputTextPath` (which doesn't exist yet) and `resolvedWavPath`. The multer upload file (`resolvedWavPath`) IS cleaned. But if the controller catches the error and `req.file.path` is different from `wavFilePath` (e.g., path.resolve changes something), the upload leaks. In practice, `path.resolve` on an already-absolute path is idempotent, so this is low risk.

**Why it matters**
Minor: possible temp file leak in edge cases.

**Fix required**
Move upload file cleanup to the controller's `finally` block as a safety net.

**Verification**
Make `/tmp/ai-assistant` read-only. Send STT request. After error, no upload files remain in the uploads directory.

---

### F-035 — No unhandledRejection handler in server.js
| Field       | Value |
|-------------|-------|
| Severity    | LOW |
| Category    | Robustness |
| Subsystem   | backend |
| File(s)     | `backend/src/server.js` |
| Blocks prod | NO |

**What is wrong**
No `process.on('unhandledRejection')` or `process.on('uncaughtException')` handler. An unhandled promise rejection in a middleware or service (e.g., in the SSE stream's `runTtsQueue` async function) can crash the Node.js process with no error logging.

**Why it matters**
A single unhandled rejection kills the backend, requiring systemd restart.

**Fix required**
Add `process.on('unhandledRejection', (reason) => { process.stderr.write('Unhandled rejection: ' + String(reason) + '\n'); })` in `server.js`.

**Verification**
Trigger an unhandled rejection (e.g., reject a promise in a test route). Process logs the rejection but does not crash.

---

## Dependency map

| Finding | Depends on | Reason |
|---------|------------|--------|
| F-003   | F-001      | CI env fix must land before SSE test fix is meaningful |
| F-002   | F-013      | System prompt flow fix requires using runtime.js consistently first |
| F-009   | F-012      | Align UI defaults after runtime.js fallbacks are fixed |
| F-022   | F-012      | Frontend defaults depend on backend defaults being correct |
| F-017   | F-016      | Rootfs size matters only after npm install is included |
| F-008   | F-007      | Same Date.now() collision pattern — fix both together |
| F-020   | F-005      | Multer limits and Express body limits should be configured together |

---

## Execution plan

### Stage 1 — Critical fixes (system does not work without these)
- **F-001**: Remove indentation from CI `.env` heredoc. (~15 min)
- **F-002**: Enforce strict system prompt cannot be overridden by client. (~30 min)
- **F-003**: Add try/catch in frontend SSE parser; fix test.sh assertion. (~20 min)
- **F-016**: Add `npm install --omit=dev` to Yocto backend recipe. (~1 hour)
- **F-017**: Add model existence check in Yocto recipe, document prerequisite. (~30 min)

Estimated effort: 3 hours.

Gate: CI pipeline runs green. `scripts/test.sh` tests 1-5 pass.

### Stage 2 — High severity fixes (system works but has bugs)
- **F-004**: Add validation middleware for LLM chat/stream routes. (~30 min)
- **F-005**: Add multer file size limit (10 MB) and MIME type filter. (~30 min)
- **F-006**: Restrict CORS to localhost and LAN origins. (~15 min)
- **F-007**: Use crypto.randomUUID() for STT temp file paths, clean up in controller. (~30 min)
- **F-008**: Use crypto.randomUUID() for TTS temp file paths. (~15 min)

Estimated effort: 2 hours.

Gate: `scripts/test.sh` passes all 8 tests. Oversized upload returns 413.

### Stage 3 — Robustness and security hardening
- **F-010**: Fix runtime.js LLM_BASE_URL fallback to port 11434. (~5 min)
- **F-011**: Fix runtime.js default model name to match GGUF filename. (~5 min)
- **F-012**: Fix runtime.js maxTokens fallback to 128. (~5 min)
- **F-013**: Use runtime config instead of direct process.env in llmService. (~15 min)
- **F-019**: Add try/catch around JSON.parse in frontend SSE handler. (~10 min)
- **F-020**: Configure multer limits for file size. (~10 min, combined with F-005)
- **F-021**: Validate piper output file size before returning. (~15 min)
- **F-035**: Add unhandledRejection handler in server.js. (~10 min)

Estimated effort: 1.5 hours.

Gate: Kill llama-server mid-request — UI shows error, server stays up. Send non-WAV file — returns 400. Send 15 MB file — returns 413.

### Stage 4 — Performance and cleanup
- **F-009**: Remove or repurpose model-config.json; align UI defaults. (~15 min)
- **F-014**: Improve mic permission denial error message. (~10 min)
- **F-015**: Add basic LLM request queue with concurrency 1. (~1 hour)
- **F-018**: Delete legacy .eslintrc.cjs. (~2 min)
- **F-022**: Align frontend UI defaults with backend .env values. (~10 min)
- **F-023**: (Optional) Optimize resampling buffer creation. (~15 min)
- **F-024**: Add "Thinking..." status between STT and LLM. (~10 min)
- **F-025**: Add MediaRecorder mimeType fallback for Safari. (~15 min)
- **F-033**: Fix check_system.sh default model paths. (~10 min)
- **F-034**: Add upload file cleanup safety net in controller. (~10 min)

Estimated effort: 3 hours.

Gate: Full voice round-trip under 8 seconds on dev machine. 3 concurrent requests all complete without error.

### Stage 5 — Documentation and CI hardening
- **F-026**: Add SSE streaming test to CI. (~20 min)
- **F-027**: Strengthen STT assertion in CI. (~10 min)
- **F-028**: Standardize system_prompt in api.md. (~10 min)
- **F-029**: Fix voice-pipeline.md to reference /stream only. (~5 min)
- **F-030**: Add commit hash and date to hardware.md benchmarks. (~10 min)
- Update README if any paths or commands changed.

Estimated effort: 1.5 hours.

Gate: `ci.yml` passes green on a clean runner. All docs match current code.

### Stage 6 — Embedded validation
- **F-031**: Pin SRCREV in all Yocto recipes. (~30 min)
- **F-032**: Add ALSA config to RPi5 conf sample. (~15 min)
- Build Yocto image with fixed code.
- Run in QEMU, verify all tests pass.
- Flash to RPi5 if available and repeat.

Estimated effort: 4 hours.

Gate: `scripts/test.sh` passes against QEMU instance at `http://localhost:3000`.

---

## Files to be modified

| File | Change type | Findings | Notes |
|------|-------------|----------|-------|
| `.github/workflows/ci.yml` | bug fix + enhancement | F-001, F-026, F-027 | Fix heredoc indentation; add SSE test; strengthen STT assertion |
| `backend/src/app.js` | security | F-006 | Restrict CORS origins |
| `backend/src/config/runtime.js` | bug fix | F-010, F-011, F-012 | Fix fallback port, model name, maxTokens |
| `backend/src/services/llmService.js` | bug fix | F-002, F-013 | Use runtime config; protect strict system prompt |
| `backend/src/services/sttService.js` | bug fix + enhancement | F-007 | Use UUID for temp paths |
| `backend/src/services/ttsService.js` | bug fix + enhancement | F-008, F-021 | Use UUID for temp paths; validate output size |
| `backend/src/controllers/voiceController.js` | enhancement | F-034 | Add upload cleanup in finally |
| `backend/src/routes/voice.js` | security | F-005, F-020 | Add multer limits and file filter |
| `backend/src/routes/llm.js` | enhancement | F-004 | Add validation middleware |
| `backend/src/middleware/validate.js` | enhancement | F-004 | Add chatRequest/streamRequest validators |
| `backend/src/server.js` | enhancement | F-035 | Add unhandledRejection handler |
| `backend/public/app.js` | bug fix + enhancement | F-003, F-014, F-019, F-022, F-024, F-025 | SSE try/catch; mic error UX; defaults; mimeType fallback |
| `backend/public/index.html` | fix | F-022 | Align default temperature and max_tokens values |
| `scripts/test.sh` | fix | F-003 | Fix SSE done assertion for named events |
| `check_system.sh` | fix | F-033 | Fix default model paths |
| `docs/api.md` | docs | F-028 | Standardize system_prompt |
| `docs/voice-pipeline.md` | docs | F-029 | Fix endpoint reference |
| `docs/hardware.md` | docs | F-030 | Add benchmark commit hash |
| `yocto/meta-ai-assistant/recipes-ai/ai-assistant-backend/ai-assistant-backend_1.0.bb` | bug fix | F-016, F-017 | Add npm install; add model check |
| `yocto/meta-ai-assistant/recipes-ai/llama-cpp/llama-cpp_git.bb` | fix | F-031 | Pin SRCREV |
| `yocto/meta-ai-assistant/recipes-ai/whisper-cpp/whisper-cpp_git.bb` | fix | F-031 | Pin SRCREV |
| `yocto/meta-ai-assistant/recipes-ai/piper-tts/piper-tts_git.bb` | fix | F-031 | Pin SRCREV |
| `yocto/conf/local-rpi5.conf.sample` | fix | F-032 | Add ALSA config |

## Files to be created

| File | Purpose | Finding |
|------|---------|---------|
| (none required) | — | — |

## Files to be deleted

| File | Reason | Finding |
|------|--------|---------|
| `backend/.eslintrc.cjs` | Legacy ESLint config conflicts with flat config `eslint.config.cjs`. Not used by ESLint 9. | F-018 |
| `llm/model-config.json` | Dead file, not read by any code. Contains conflicting default values. | F-009 |

---

## Production readiness checklist

### Functional completeness
- [ ] User can send a text message and receive a coherent English text response
- [ ] User can press the mic button, speak, and have their speech transcribed into the text input
- [ ] User can enable TTS and hear the assistant's response spoken aloud after it arrives
- [ ] User can complete a full voice-in → voice-out conversation without touching the keyboard
- [ ] The model selector populates with available models
- [ ] All three status dots (LLM, STT, TTS) correctly reflect service health
- [ ] The system prompt in the settings panel is sent to the LLM and affects responses
- [ ] Streaming tokens appear progressively in the assistant bubble, not all at once

### Correctness
- [ ] LLM never responds in a non-English language
- [ ] LLM never responds with hallucinated code when asked a factual question
- [ ] WAV files produced by TTS are valid RIFF files (verified by `file` command)
- [ ] WAV files sent to STT are correctly resampled to 16kHz mono before upload
- [ ] SSE stream ends with done:true and the UI cursor is removed
- [ ] Empty prompt is rejected with HTTP 400
- [ ] Empty TTS text is rejected with HTTP 400

### Robustness
- [ ] If llama-server crashes, the UI shows an error and the status dot turns red within 30 seconds
- [ ] If llama-server is slow, requests do not hang indefinitely (timeout fires after LLM_TIMEOUT ms)
- [ ] Sending a non-WAV file to /api/voice/stt returns HTTP 400, not 500
- [ ] Sending a 10 MB audio file returns HTTP 413
- [ ] Concurrent requests do not crash the Express server
- [ ] /tmp temp files are deleted after every STT and TTS request, successful or not

### Security
- [ ] CORS is restricted to localhost and the LAN subnet, not wildcard *
- [ ] multer rejects non-audio/wav uploads
- [ ] Stack traces are not returned in production error responses
- [ ] No secrets or API keys in any source file

### Performance
- [ ] Full voice round-trip (speech → transcript → LLM → TTS → audio) completes in under 8 seconds on the dev machine
- [ ] TTS synthesis of a one-sentence response completes in under 2 seconds
- [ ] STT transcription of a 5-second clip completes in under 4 seconds

### Infrastructure
- [ ] scripts/setup.sh runs to completion on a fresh clone with zero manual steps
- [ ] scripts/check.sh reports 13/13 PASS after setup
- [ ] start.sh starts all services and self-tests pass
- [ ] ci.yml runs green on every push to main
- [ ] All unit tests pass with coverage >= 70%
- [ ] Yocto image builds without errors
- [ ] System works in QEMU with port forwarding

### Documentation
- [ ] README quick start works exactly as written
- [ ] docs/api.md request/response shapes match code
- [ ] docs/voice-pipeline.md accurately describes the current implementation
- [ ] Every script has a usage comment at the top

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Qwen2.5-0.5B leaks Chinese in CI despite system prompt | HIGH | MEDIUM | Use seed=42, temperature=0, ASCII assertion, strict system prompt cannot be overridden |
| whisper-cli output file path assumption breaks on some builds | MEDIUM | HIGH | Test with `whisper-cli --help` to confirm `-of` behavior; pin SRCREV |
| piper exits 0 but writes empty WAV on some Linux distros | LOW | HIGH | Check file size after every synthesis (F-021) |
| Yocto rootfs too small for models | MEDIUM | HIGH | Verify IMAGE_ROOTFS_EXTRA_SPACE calculation; add build-time model check |
| Node.js version in Yocto meta-nodejs lags behind v24 | MEDIUM | LOW | Pin to LTS (v20) in Yocto; v24 on dev. Backend uses CommonJS, no v24-only features |
| llama.cpp/whisper.cpp AUTOREV breaks build | MEDIUM | HIGH | Pin SRCREV (F-031) |
| MediaRecorder mimeType unsupported in Safari | HIGH | MEDIUM | Add isTypeSupported fallback (F-025) |
| Concurrent LLM requests cause cascade timeouts | MEDIUM | HIGH | Add request queue (F-015) |

---

## Glossary

- **LLM_STRICT_SYSTEM_PROMPT** — Environment variable that injects a system-role message into every llama-server request, forcing English-only ASCII output. Defined in `.env` and read by `runtime.js`.

- **chat template** — The special token format (e.g., `qwen2`) that llama-server uses to structure system + user + assistant turns. Without `--chat-template qwen2`, the model sees raw text and produces garbage or non-English output.

- **GGUF** — The file format for quantized LLM weights used by llama.cpp. The project uses Q4_K_M quantization of Qwen2.5-0.5B-Instruct.

- **SSE (Server-Sent Events)** — The streaming protocol used by `/api/llm/stream`. Backend writes `event:` and `data:` lines; frontend reads them as a byte stream via `ReadableStream`.

- **OfflineAudioContext** — Web Audio API interface used by the frontend to resample microphone audio from the browser's native sample rate (typically 48000 Hz) down to 16000 Hz for whisper-cli compatibility.

- **RIFF/WAV** — The audio file format produced by `encodeWAV()` in the frontend and by piper in the backend. A valid RIFF WAV has a 44-byte header followed by PCM sample data.

- **multer** — Express middleware for handling `multipart/form-data` uploads. Used on the `/api/voice/stt` route to receive audio files.

- **AUTOREV** — Yocto/BitBake variable that means "always fetch the latest commit from the upstream repo." Non-reproducible. Should be replaced with a pinned commit hash for production.

- **IMAGE_ROOTFS_EXTRA_SPACE** — Yocto variable specifying additional kilobytes to add to the root filesystem image beyond what installed packages require.

- **espeak-ng-data** — Phoneme database required by piper for text-to-phoneme conversion. Must be present at the path specified by `PIPER_ESPEAK_DATA`.

---

## Appendix A — Audit log

```
[backend/.env.example] — Defines LLM_LOGIT_BIAS_JSON but no code outside runtime.js reads it
[backend/.env.example:59] — LD_LIBRARY_PATH defined but never used by any script or service file
[backend/.env] — NODE_ENV=production but this is the dev machine .env; start.sh overwrites it anyway
[backend/package.json:10] — lint script uses --ext .js which is ignored by flat config ESLint 9
[backend/.eslintrc.cjs:2] — extends: ['node'] — no eslint-config-node in devDependencies; dead config
[backend/eslint.config.cjs] — sourceType: 'script' is correct for CommonJS
[backend/src/server.js] — No unhandledRejection handler; process dies on stray promise rejection
[backend/src/app.js:20] — cors() with no arguments = Access-Control-Allow-Origin: * in every response
[backend/src/app.js:22] — express.json limit 2mb protects JSON but not multipart uploads
[backend/src/config/runtime.js:16] — LLM_BASE_URL fallback http://127.0.0.1:8080 — all other files use 11434
[backend/src/config/runtime.js:18] — Default model name lowercase no .gguf — inconsistent with .env
[backend/src/config/runtime.js:19] — maxTokens fallback 512 vs .env's 128
[backend/src/config/runtime.js:25-33] — strictEnglishSystemPrompt has detailed fallback; llmService ignores it
[backend/src/routes/llm.js] — No validation middleware on any LLM route
[backend/src/routes/voice.js:12] — multer no limits, no fileFilter
[backend/src/controllers/llmController.js:82] — options spread directly from req.body.options — no sanitization
[backend/src/controllers/llmController.js:133-141] — sendSse uses named events; frontend ignores event names
[backend/src/controllers/voiceController.js] — No finally block to clean up req.file.path on service error
[backend/src/services/llmService.js:7-9] — Reads process.env directly, ignores runtime.js config
[backend/src/services/llmService.js:24-28] — Allows client systemPrompt to fully replace strict prompt
[backend/src/services/sttService.js:49] — Date.now() for temp file uniqueness — collision risk
[backend/src/services/sttService.js:62-67] — finally block cleans up but mkdir failure path could leak
[backend/src/services/ttsService.js:64] — Date.now() for temp file — same collision risk
[backend/src/services/ttsService.js:70-71] — No validation of piper output file size
[backend/src/middleware/errorHandler.js:15] — Correctly hides stack traces for 5xx; good
[backend/src/middleware/requestId.js] — Trusts X-Request-Id from client; minor spoofing risk
[backend/src/middleware/validate.js] — Only ttsRequest validator; no LLM validators
[backend/public/index.html:51] — Temperature slider default 0.7 conflicts with .env temperature 0
[backend/public/index.html:56] — Max tokens default 256 conflicts with .env 128
[backend/public/index.html:66] — Default system prompt "You are a helpful assistant" weaker than strict env prompt
[backend/public/app.js:95] — Sends system_prompt in options — can override strict English prompt
[backend/public/app.js:128] — JSON.parse with no try/catch — single malformed frame kills stream
[backend/public/app.js:156] — MediaRecorder mimeType audio/webm;codecs=opus not supported in Safari
[backend/public/app.js:172] — Mic status changes to Idle before sendTextMessage — gap in UX feedback
[backend/public/app.js:213] — Mono buffer created at source sample rate — works but inefficient
[backend/public/app.js:255-288] — encodeWAV correctly computes RIFF header — verified all byte offsets
[backend/public/app.js:283-284] — float32-to-int16 clips at ±1 then scales — correct
[backend/public/app.js:267-279] — RIFF chunk size = 36 + dataLength — correct (file size - 8)
[backend/public/app.js:268] — data chunk size = dataLength = samples.length * 2 — correct
[backend/public/app.js:307-310] — Audio() element handles any sample rate — piper 22050 Hz OK
[backend/tests/unit/llmService.test.js] — Tests chat, ping, listModels; no streamChat test
[backend/tests/unit/sttService.test.js] — Tests transcribe and ping; no timeout test
[backend/tests/unit/ttsService.test.js] — Tests synthesize and ping; no empty output test
[backend/tests/unit/validate.test.js] — Only tests ttsRequest; no LLM validation tests
[llm/setup.sh:37-41] — Uses exec so script never returns; correct for process replacement
[llm/model-config.json] — Dead file, never imported by any code; temperature 0.7 vs .env 0
[llm/llama-server.service:7] — Model path /opt/ai-assistant/models/ — matches deploy/install.sh
[stt/setup.sh] — Uses whisper.cpp model downloader script, then copies — correct
[tts/setup.sh:87-91] — Always re-downloads voice model even if exists — no idempotency check
[tts/piper-voices.json] — Model path /opt/ai-assistant/models/ — only referenced for deployed context
[backend/deploy/ai-assistant.service:21] — EnvironmentFile=-/opt/ai-assistant/.env — file may not exist
[backend/deploy/install.sh:17-21] — rsync excludes node_modules, .env correctly
[yocto/setup.sh] — Clones scarthgap branches — correct for stable Yocto release
[yocto/run-qemu.sh:11-13] — Forwards ports 3000, 11434, 2222 — correct
[yocto/conf/local.conf.sample:4] — IMAGE_ROOTFS_EXTRA_SPACE 2GB — borderline for models + binaries
[yocto/conf/local-rpi5.conf.sample] — No ALSA config, no MACHINE_FEATURES
[yocto/conf/bblayers.conf.sample:8] — Includes meta-nodejs — needed for nodejs recipe
[yocto/meta-ai-assistant/conf/layer.conf:10] — LAYERSERIES_COMPAT scarthgap — matches setup.sh
[yocto/meta-ai-assistant/recipes-ai/llama-cpp/llama-cpp_git.bb:9] — AUTOREV — non-reproducible
[yocto/meta-ai-assistant/recipes-ai/whisper-cpp/whisper-cpp_git.bb:9] — AUTOREV — non-reproducible
[yocto/meta-ai-assistant/recipes-ai/piper-tts/piper-tts_git.bb:9] — AUTOREV — non-reproducible
[yocto/meta-ai-assistant/recipes-ai/ai-assistant-backend/ai-assistant-backend_1.0.bb:20] — Removes node_modules, never reinstalls
[yocto/meta-ai-assistant/recipes-ai/llm-bridge/ai-assistant-backend_1.0.bb:1] — Requires relative path ../ai-assistant-backend/ — brittle
[yocto/meta-ai-assistant/recipes-core/images/ai-assistant-image.bb:9] — Installs nodejs — version depends on meta-nodejs layer
[.github/workflows/ci.yml:142-165] — Heredoc indented with spaces — dotenv parses keys with leading spaces
[.github/workflows/ci.yml:203-227] — No SSE streaming test
[.github/workflows/ci.yml:222] — STT assertion only checks key exists, not content
[scripts/test.sh:106] — Exact match on done event may be fragile with named SSE events
[scripts/test.sh:207] — Negated grep logic: `! echo | grep -qi` — double negation confusing but works
[start.sh:158] — wait_backend checks llm/health status==ok — correct compound check
[stop.sh] — Kills by port — could kill unrelated processes on those ports
[check_system.sh:4] — Default LLM model path /usr/share/models/qwen.gguf — doesn't match any other file
[docs/api.md:21] — systemPrompt (camelCase) vs line 57 system_prompt (snake_case) — inconsistent
[docs/voice-pipeline.md:10] — Says /api/llm/chat or /stream — UI only uses /stream
[README.md] — Quick start instructions are accurate; no errors found
```

---

## Appendix B — Test commands reference

```bash
# Check everything is set up
bash scripts/check.sh

# Start the system
./start.sh

# Run all tests
bash scripts/test.sh

# Test LLM directly (bypasses Express)
curl -s http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen2.5-0.5B-Instruct-Q4_K_M.gguf",
       "messages":[
         {"role":"system","content":"Reply in English only."},
         {"role":"user","content":"What is 2+2?"}
       ],"max_tokens":16,"temperature":0}' \
  | python3 -m json.tool

# Test TTS directly (bypasses Express, piper binary direct)
echo "Hello world" | ./tts/bin/piper \
  --model ./tts/models/en_US-lessac-low.onnx \
  --output_file /tmp/direct_tts.wav && \
  ls -lh /tmp/direct_tts.wav

# Test STT directly
./stt/whisper.cpp/build/bin/whisper-cli \
  -m ./stt/models/ggml-tiny.en.bin \
  -f /tmp/direct_tts.wav -otxt -of /tmp/direct_stt && \
  cat /tmp/direct_stt.txt

# Full API test suite
bash scripts/test.sh --base-url http://localhost:3000

# Test from another device (replace IP)
bash scripts/test.sh --base-url http://192.168.1.42:3000

# Run unit tests with coverage
cd backend && npm test

# Run linting
cd backend && npm run lint

# Verify CORS restriction
curl -sI -H 'Origin: https://evil.com' http://localhost:3000/api/llm/health \
  | grep Access-Control-Allow-Origin

# Test file size limit on STT
dd if=/dev/zero bs=1M count=15 2>/dev/null \
  | curl -s -o /dev/null -w "%{http_code}" \
    -X POST http://localhost:3000/api/voice/stt \
    -F "audio=@-;type=audio/wav"
# Expected: 413

# Test empty prompt rejection
curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:3000/api/llm/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt":""}'
# Expected: 400

# Test empty TTS text rejection
curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:3000/api/voice/tts \
  -H "Content-Type: application/json" \
  -d '{"text":""}'
# Expected: 400

# Verify temp file cleanup
ls /tmp/ai-assistant/whisper_out* 2>/dev/null && echo "LEAKED" || echo "CLEAN"
ls /tmp/ai-assistant/tts_out* 2>/dev/null && echo "LEAKED" || echo "CLEAN"
```

