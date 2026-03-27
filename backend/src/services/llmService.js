const axios = require('axios');

const baseURL = process.env.LLM_BASE_URL || 'http://localhost:11434';
const timeout = Number(process.env.LLM_TIMEOUT || 60000);
const defaultModel = process.env.LLM_DEFAULT_MODEL || 'qwen2.5:0.5b';

const client = axios.create({
  baseURL,
  timeout,
});

async function chat(prompt, model = defaultModel, options = {}) {
  const payload = {
    model,
    messages: [{ role: 'user', content: prompt }],
    max_tokens: Number(options.max_tokens || 512),
    temperature: Number(options.temperature || 0.7),
    stream: false,
  };

  const response = await client.post('/v1/chat/completions', payload);
  return response.data?.choices?.[0]?.message?.content || '';
}

async function streamChat(prompt, model = defaultModel, options = {}) {
  const payload = {
    model,
    messages: [{ role: 'user', content: prompt }],
    max_tokens: Number(options.max_tokens || 512),
    temperature: Number(options.temperature || 0.7),
    stream: true,
  };

  return client.post('/v1/chat/completions', payload, { responseType: 'stream' });
}

async function ping() {
  const response = await client.get('/health');
  return { ok: true, ...response.data };
}

async function listModels() {
  const response = await client.get('/v1/models');
  return response.data;
}

module.exports = {
  chat,
  streamChat,
  ping,
  listModels,
};
