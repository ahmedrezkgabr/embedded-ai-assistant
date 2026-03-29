# API Reference

Base URL: `http://<host>:3000`

## LLM Endpoints

### POST `/api/llm/chat`

Request body:

```json
{
  "prompt": "Explain edge AI in one sentence.",
  "model": "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf",
  "options": {
    "temperature": 0,
    "max_tokens": 128,
    "seed": 42,
    "top_p": 0.2,
    "repeat_penalty": 1.1,
    "systemPrompt": "You are a helpful assistant."
  }
}
```

Response body:

```json
{
  "response": "Edge AI runs models directly on local devices.",
  "model": "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf",
  "duration_ms": 213,
  "requestId": "9d0ac2e1-7c4c-4ab1-8d70-3e4d89ec43cf"
}
```

Validation error (`400`):

```json
{
  "error": "prompt is required",
  "requestId": "9d0ac2e1-7c4c-4ab1-8d70-3e4d89ec43cf"
}
```

### POST `/api/llm/stream`

Request body (same shape as `/api/llm/chat` with optional stream extras):

```json
{
  "prompt": "stream hello",
  "model": "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf",
  "options": {
    "temperature": 0,
    "max_tokens": 128,
    "system_prompt": "You are a helpful assistant."
  },
  "tts_stream": true,
  "voice": "en_US-lessac-low"
}
```

Response content type: `text/event-stream`

SSE payload examples (`data:` lines):

```json
{"token":"Hello","done":false}
{"type":"sentence","sentence":"Hello world."}
{"type":"audio","sentence":"Hello world.","mime":"audio/wav","audio_base64":"..."}
{"done":true}
```

### GET `/api/llm/health`

Response body:

```json
{
  "ok": true,
  "status": "ok",
  "latency_ms": 3,
  "requestId": "9d0ac2e1-7c4c-4ab1-8d70-3e4d89ec43cf"
}
```

### GET `/api/llm/models`

Response body:

```json
{
  "data": [
    {
      "id": "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
    }
  ],
  "requestId": "9d0ac2e1-7c4c-4ab1-8d70-3e4d89ec43cf"
}
```

## Voice Endpoints

### POST `/api/voice/stt`

Request: `multipart/form-data`, field name `audio` (WAV recommended at 16kHz mono).

Response body:

```json
{
  "transcript": "turn on the desk lamp",
  "duration_ms": 1480,
  "requestId": "9d0ac2e1-7c4c-4ab1-8d70-3e4d89ec43cf"
}
```

Validation error (`400`):

```json
{
  "error": "audio file is required",
  "requestId": "9d0ac2e1-7c4c-4ab1-8d70-3e4d89ec43cf"
}
```

### POST `/api/voice/tts`

Request body:

```json
{
  "text": "Hello from the embedded assistant.",
  "voice": "en_US-lessac-low"
}
```

Response:
- HTTP `200`
- `Content-Type: audio/wav`
- Binary WAV body

Validation error (`400`):

```json
{
  "error": "invalid request",
  "details": [
    {
      "type": "field",
      "msg": "Invalid value",
      "path": "text",
      "location": "body"
    }
  ],
  "requestId": "9d0ac2e1-7c4c-4ab1-8d70-3e4d89ec43cf"
}
```

### GET `/api/voice/health`

Response body:

```json
{
  "stt": {
    "ok": true,
    "binary": true,
    "model": true
  },
  "tts": {
    "ok": true,
    "binary": true,
    "model": true,
    "model_json": true
  },
  "requestId": "9d0ac2e1-7c4c-4ab1-8d70-3e4d89ec43cf"
}
```
