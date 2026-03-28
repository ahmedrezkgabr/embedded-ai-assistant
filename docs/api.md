# API Reference

Base URL: `http://<host>:3000`

## LLM Endpoints

### `POST /api/llm/chat`

Request body:

```json
{
  "prompt": "Explain edge AI in one sentence.",
  "model": "qwen2.5:0.5b",
  "options": {
    "temperature": 0.7,
    "max_tokens": 256
  }
}
```

Response body:

```json
{
  "response": "Edge AI runs models directly on local devices.",
  "requestId": "..."
}
```

Example:

```bash
curl -s -X POST http://localhost:3000/api/llm/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt":"say hi"}'
```

### `POST /api/llm/stream`

Request body: same as `/api/llm/chat`

Optional fields:

```json
{
  "tts_stream": true,
  "voice": "en_US-lessac-low"
}
```

Response: `text/event-stream`

Events:

- `event: token` + `data: {"token":"...","done":false}`
- `event: sentence` + `data: {"type":"sentence","sentence":"..."}`
- `event: audio` + `data: {"type":"audio","sentence":"...","mime":"audio/wav","audio_base64":"..."}` (only when `tts_stream=true`)
- `event: done` + `data: {"done":true}`

Example:

```bash
curl -N -X POST http://localhost:3000/api/llm/stream \
  -H "Content-Type: application/json" \
  -d '{"prompt":"stream hello", "tts_stream": true, "voice": "en_US-lessac-low"}'
```

### `GET /api/llm/health`

Response:

```json
{
  "ok": true,
  "requestId": "..."
}
```

### `GET /api/llm/models`

Response:

```json
{
  "data": [
    { "id": "qwen2.5:0.5b" }
  ],
  "requestId": "..."
}
```

## Voice Endpoints

### `POST /api/voice/stt`

Request: `multipart/form-data`, field name: `audio` (WAV 16kHz mono)

Response:

```json
{
  "transcript": "turn on the desk lamp",
  "duration_ms": 1480,
  "requestId": "..."
}
```

Example:

```bash
curl -s -X POST http://localhost:3000/api/voice/stt \
  -F "audio=@recording.wav"
```

### `POST /api/voice/tts`

Request:

```json
{
  "text": "Hello from the embedded assistant.",
  "voice": "en_US-lessac-low"
}
```

Response:

- Content-Type: `audio/wav`
- Binary WAV payload

Example:

```bash
curl -s -X POST http://localhost:3000/api/voice/tts \
  -H "Content-Type: application/json" \
  -d '{"text":"hello"}' > /tmp/test.wav
```

### `GET /api/voice/health`

Response:

```json
{
  "stt": { "ok": true, "binary": true, "model": true },
  "tts": { "ok": true, "binary": true, "model": true },
  "requestId": "..."
}
```
