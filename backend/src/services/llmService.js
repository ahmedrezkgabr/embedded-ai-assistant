const axios = require('axios');
const runtime = require('../config/runtime');

const baseURL = runtime.llm.baseUrl;
const timeout = runtime.llm.timeoutMs;
const defaultModel = runtime.llm.defaultModel;
const DEFAULT_SYSTEM_PROMPT =
  process.env.LLM_STRICT_SYSTEM_PROMPT ||
  process.env.LLM_SYSTEM_PROMPT ||
  'You are a helpful assistant. Always reply in English. Be concise.';

function parseLogitBias() {
  if (!runtime.llm.logitBiasJson) {
    return undefined;
  }

  try {
    const parsed = JSON.parse(runtime.llm.logitBiasJson);
    return parsed && typeof parsed === 'object' ? parsed : undefined;
  } catch {
    return undefined;
  }
}

function buildMessages(prompt, options = {}) {
  const systemPrompt =
    options.systemPrompt ||
    options.system_prompt ||
    DEFAULT_SYSTEM_PROMPT;

  return [
    { role: 'system', content: systemPrompt },
    { role: 'user', content: prompt },
  ];
}

function buildPayload(prompt, model, options = {}, stream = false) {
  const logitBias = parseLogitBias();

  return {
    model: model || defaultModel,
    messages: buildMessages(prompt, options),
    max_tokens: Number(options.max_tokens ?? 64),
    temperature: Number(options.temperature ?? 0),
    top_p: Number(options.top_p ?? 0.1),
    repeat_penalty: Number(options.repeat_penalty ?? 1.1),
    seed: Number(options.seed ?? 42),
    frequency_penalty: Number(options.frequency_penalty ?? runtime.llm.frequencyPenalty),
    presence_penalty: Number(options.presence_penalty ?? runtime.llm.presencePenalty),
    stream,
    ...(logitBias ? { logit_bias: logitBias } : {}),
  };
}

const client = axios.create({
  baseURL,
  timeout,
});

function createLlmUnavailableError(error) {
  const wrapped = new Error('LLM service unavailable');
  if (error?.response?.status) {
    wrapped.status = error.response.status;
  } else {
    wrapped.status = 503;
  }
  return wrapped;
}

function normalizeAsciiResponse(text) {
  const raw = String(text || '');
  const asciiOnly = raw
    .replace(/[^\x20-\x7E\n\r\t]/g, '')
    .replace(/[ \t]+/g, ' ')
    .trim();

  if (asciiOnly) {
    return asciiOnly;
  }

  return 'I can only reply using English ASCII text.';
}

async function chat(prompt, model = defaultModel, options = {}) {
  const payload = buildPayload(prompt, model, options, false);

  try {
    const requestConfig = options.signal ? { signal: options.signal } : undefined;
    const response = requestConfig
      ? await client.post('/v1/chat/completions', payload, requestConfig)
      : await client.post('/v1/chat/completions', payload);
    const content = response.data?.choices?.[0]?.message?.content || '';

    return {
      response: normalizeAsciiResponse(content),
      model: response.data?.model || model,
    };
  } catch (error) {
    throw createLlmUnavailableError(error);
  }
}

async function streamChat(prompt, model = defaultModel, options = {}) {
  const payload = buildPayload(prompt, model, options, true);

  try {
    const requestConfig = {
      responseType: 'stream',
      ...(options.signal ? { signal: options.signal } : {}),
    };
    return await client.post('/v1/chat/completions', payload, requestConfig);
  } catch (error) {
    throw createLlmUnavailableError(error);
  }
}

async function ping() {
  const started = Date.now();
  try {
    const response = await client.get('/health');
    const status = response.data?.status || 'ok';
    return {
      ok: status === 'ok',
      status,
      latency_ms: Date.now() - started,
    };
  } catch {
    return {
      ok: false,
      status: 'unreachable',
      latency_ms: Date.now() - started,
    };
  }
}

async function listModels() {
  try {
    const response = await client.get('/v1/models');
    const models = Array.isArray(response.data?.data) ? response.data.data : [];
    return { models };
  } catch (error) {
    throw createLlmUnavailableError(error);
  }
}

module.exports = {
  chat,
  streamChat,
  ping,
  listModels,
};
