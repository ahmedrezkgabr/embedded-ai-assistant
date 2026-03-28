const axios = require('axios');

const baseURL = process.env.LLM_BASE_URL || 'http://localhost:11434';
const timeout = Number(process.env.LLM_TIMEOUT || 60000);
const defaultModel = process.env.LLM_DEFAULT_MODEL || 'qwen2.5:0.5b';

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

async function chat(prompt, model = defaultModel, options = {}) {
  const payload = {
    model,
    messages: [{ role: 'user', content: prompt }],
    max_tokens: Number(options.max_tokens || 512),
    temperature: Number(options.temperature || 0.7),
    stream: false,
  };

  try {
    const response = await client.post('/v1/chat/completions', payload);
    return {
      response: response.data?.choices?.[0]?.message?.content || '',
      model: response.data?.model || model,
    };
  } catch (error) {
    throw createLlmUnavailableError(error);
  }
}

async function streamChat(prompt, model = defaultModel, options = {}) {
  const payload = {
    model,
    messages: [{ role: 'user', content: prompt }],
    max_tokens: Number(options.max_tokens || 512),
    temperature: Number(options.temperature || 0.7),
    stream: true,
  };

  try {
    return await client.post('/v1/chat/completions', payload, { responseType: 'stream' });
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
