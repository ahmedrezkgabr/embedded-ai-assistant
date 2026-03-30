const axios = require('axios');
const runtime = require('../config/runtime');

const baseURL = runtime.llm.baseUrl;
const timeout = runtime.llm.timeoutMs;
const defaultModel = runtime.llm.defaultModel;
const DEFAULT_SYSTEM_PROMPT = runtime.llm.strictEnglishSystemPrompt;

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
  const customSystemPrompt = String(
    options.systemPrompt || options.system_prompt || ''
  ).trim();

  const messages = [
    { role: 'system', content: DEFAULT_SYSTEM_PROMPT },
  ];

  if (customSystemPrompt && customSystemPrompt !== DEFAULT_SYSTEM_PROMPT) {
    messages.push({ role: 'system', content: customSystemPrompt });
  }

  messages.push({ role: 'user', content: prompt });
  return messages;
}

function buildPayload(prompt, model, options = {}, stream = false) {
  const logitBias = parseLogitBias();

  return {
    model: model || defaultModel,
    messages: buildMessages(prompt, options),
    max_tokens: Number(options.max_tokens ?? runtime.llm.maxTokens),
    temperature: Number(options.temperature ?? runtime.llm.temperature),
    top_p: Number(options.top_p ?? runtime.llm.topP),
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

let activeRequests = 0;
const MAX_CONCURRENT = 1;
const queue = [];

function releaseQueue() {
  if (queue.length > 0) {
    const nextTask = queue.shift();
    nextTask();
  } else {
    activeRequests = Math.max(0, activeRequests - 1);
  }
}

function acquireQueue() {
  return new Promise((resolve, reject) => {
    if (activeRequests < MAX_CONCURRENT) {
      activeRequests++;
      resolve();
    } else if (queue.length >= 5) {
      const err = new Error('Too many requests in queue');
      err.status = 429;
      reject(err);
    } else {
      queue.push(resolve);
    }
  });
}

function createLlmUnavailableError(error) {
  const wrapped = new Error('LLM service unavailable');
  if (error?.response?.status) {
    wrapped.status = error.response.status;
  } else {
    wrapped.status = error?.status || 503;
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
  const started = Date.now();
  const payload = buildPayload(prompt, model, options, false);

  // Log token count estimate for debugging (word count ≈ token count)
  const estimatedTokens = payload.messages
    .map(m => m.content.split(' ').length)
    .reduce((a, b) => a + b, 0);
  console.log(`[llmService] estimated tokens: ${estimatedTokens}, model: ${payload.model}, messages: ${payload.messages.length}`);

  await acquireQueue();
  try {
    const requestConfig = options.signal ? { signal: options.signal } : undefined;
    const response = requestConfig
      ? await client.post('/v1/chat/completions', payload, requestConfig)
      : await client.post('/v1/chat/completions', payload);
    const content = response.data?.choices?.[0]?.message?.content || '';

    return {
      response: normalizeAsciiResponse(content),
      model: response.data?.model || model,
      duration_ms: Date.now() - started,
    };
  } catch (error) {
    throw createLlmUnavailableError(error);
  } finally {
    releaseQueue();
  }
}

async function streamChat(prompt, model = defaultModel, options = {}) {
  const payload = buildPayload(prompt, model, options, true);

  await acquireQueue();
  try {
    const requestConfig = {
      responseType: 'stream',
      ...(options.signal ? { signal: options.signal } : {}),
    };
    const response = await client.post('/v1/chat/completions', payload, requestConfig);

    let released = false;
    const releaseOnce = () => {
      if (!released) {
        released = true;
        releaseQueue();
      }
    };

    response.data.on('end', releaseOnce);
    response.data.on('error', releaseOnce);
    response.data.on('close', releaseOnce);

    if (options.signal) {
      options.signal.addEventListener('abort', releaseOnce);
    }

    return response;
  } catch (error) {
    releaseQueue();
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
    return Array.isArray(response.data?.data) ? response.data.data : [];
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
