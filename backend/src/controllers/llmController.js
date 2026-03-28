const llmService = require('../services/llmService');

async function chat(req, res, next) {
  const started = Date.now();
  try {
    const prompt = String(req.body?.prompt || '').trim();
    if (!prompt) {
      return res.status(400).json({ error: 'prompt is required', requestId: req.requestId });
    }

    const model = req.body?.model;
    const options = {
      ...(req.body?.options || {}),
      ...(req.body?.temperature !== undefined ? { temperature: req.body.temperature } : {}),
      ...(req.body?.max_tokens !== undefined ? { max_tokens: req.body.max_tokens } : {}),
    };
    const result = await llmService.chat(prompt, model, options);

    return res.json({
      response: result.response,
      model: result.model,
      duration_ms: Date.now() - started,
      requestId: req.requestId,
    });
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
    const options = {
      ...(req.body?.options || {}),
      ...(req.body?.temperature !== undefined ? { temperature: req.body.temperature } : {}),
      ...(req.body?.max_tokens !== undefined ? { max_tokens: req.body.max_tokens } : {}),
    };
    const result = await llmService.chat(prompt, model, options);

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');
    if (typeof res.flushHeaders === 'function') {
      res.flushHeaders();
    }

    const chunks = String(result.response || '')
      .split(/\s+/)
      .map((token) => token.trim())
      .filter(Boolean);

    let index = 0;
    let closed = false;

    const sendDone = () => {
      if (closed || res.writableEnded) {
        return;
      }
      res.write(`data: ${JSON.stringify({ done: true })}\n\n`);
      res.end();
      closed = true;
    };

    const timer = setInterval(() => {
      if (closed || res.writableEnded) {
        clearInterval(timer);
        return;
      }

      if (index >= chunks.length) {
        clearInterval(timer);
        sendDone();
        return;
      }

      const token = index === 0 ? chunks[index] : ` ${chunks[index]}`;
      res.write(`data: ${JSON.stringify({ token, done: false })}\n\n`);
      index += 1;
    }, 25);

    const forceDone = setTimeout(() => {
      clearInterval(timer);
      sendDone();
    }, 25000);

    req.on('close', () => {
      closed = true;
      clearInterval(timer);
      clearTimeout(forceDone);
      if (!res.writableEnded) {
        res.end();
      }
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
