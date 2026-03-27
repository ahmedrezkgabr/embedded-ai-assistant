const llmService = require('../services/llmService');

async function chat(req, res, next) {
  try {
    const prompt = String(req.body?.prompt || '').trim();
    if (!prompt) {
      return res.status(400).json({ error: 'prompt is required', requestId: req.requestId });
    }

    const model = req.body?.model;
    const options = req.body?.options || {};
    const response = await llmService.chat(prompt, model, options);

    return res.json({ response, requestId: req.requestId });
  } catch (error) {
    return next(error);
  }
}

async function stream(req, res, next) {
  try {
    const prompt = String(req.body?.prompt || '').trim();
    if (!prompt) {
      return res.status(400).json({ error: 'prompt is required', requestId: req.requestId });
    }

    const model = req.body?.model;
    const options = req.body?.options || {};
    const upstream = await llmService.streamChat(prompt, model, options);

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    upstream.data.on('data', (chunk) => {
      res.write(`data: ${chunk.toString()}\n\n`);
    });

    upstream.data.on('end', () => {
      res.write('data: {"done":true}\n\n');
      res.end();
    });

    upstream.data.on('error', (error) => {
      next(error);
    });

    req.on('close', () => {
      upstream.data.destroy();
    });

    return undefined;
  } catch (error) {
    return next(error);
  }
}

async function health(req, res, next) {
  try {
    const ping = await llmService.ping();
    return res.json({ ...ping, requestId: req.requestId });
  } catch (error) {
    return next(error);
  }
}

async function models(req, res, next) {
  try {
    const data = await llmService.listModels();
    return res.json({ ...data, requestId: req.requestId });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  chat,
  stream,
  health,
  models,
};
