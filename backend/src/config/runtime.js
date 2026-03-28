const path = require('path');

function toNumber(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

const tmpDir = process.env.TMP_DIR || '/tmp';

module.exports = {
  server: {
    port: toNumber(process.env.PORT, 3000),
    logFile: process.env.LOG_FILE || path.join(tmpDir, 'ai-assistant', 'backend.log'),
  },
  llm: {
    baseUrl: process.env.LLM_BASE_URL || 'http://127.0.0.1:8080',
    timeoutMs: toNumber(process.env.LLM_TIMEOUT, 60000),
    defaultModel: process.env.LLM_DEFAULT_MODEL || 'qwen2.5-0.5b-instruct-q4_k_m',
    maxTokens: toNumber(process.env.LLM_MAX_TOKENS, 512),
    temperature: toNumber(process.env.LLM_TEMPERATURE, 0.2),
    topP: toNumber(process.env.LLM_TOP_P, 0.9),
    frequencyPenalty: toNumber(process.env.LLM_FREQUENCY_PENALTY, 0.6),
    presencePenalty: toNumber(process.env.LLM_PRESENCE_PENALTY, 0.2),
    logitBiasJson: process.env.LLM_LOGIT_BIAS_JSON || '',
    strictEnglishSystemPrompt:
      process.env.LLM_STRICT_SYSTEM_PROMPT ||
      [
        'You are an embedded Linux voice assistant running offline.',
        'Always reply in English only.',
        'Do not use Chinese, Japanese, Korean, or other non-English scripts.',
        'If the user writes in another language, translate intent to English and answer in English.',
        'Keep responses concise, factual, and safe for production operations.',
      ].join(' '),
  },
  stt: {
    whisperBin: process.env.WHISPER_BIN || '/usr/bin/whisper-cli',
    whisperModel: process.env.WHISPER_MODEL || '/usr/share/models/ggml-tiny.en.bin',
    timeoutMs: toNumber(process.env.WHISPER_TIMEOUT, 30000),
    outputPrefix: path.join(tmpDir, 'ai-assistant', 'whisper_out'),
  },
  tts: {
    piperBin: process.env.PIPER_BIN || '/usr/bin/piper',
    defaultVoice: process.env.PIPER_VOICE || '/usr/share/models/en_US-lessac-low.onnx',
    voiceDir: process.env.PIPER_VOICE_DIR || '/usr/share/models',
    timeoutMs: toNumber(process.env.PIPER_TIMEOUT, 20000),
    outputPrefix: path.join(tmpDir, 'ai-assistant', 'tts_out'),
  },
  uploads: {
    dir: process.env.UPLOAD_DIR || path.join(tmpDir, 'ai-assistant', 'uploads'),
  },
};
