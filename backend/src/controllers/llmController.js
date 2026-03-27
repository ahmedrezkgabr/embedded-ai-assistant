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
    res.setHeader('X-Accel-Buffering', 'no');
    res.flushHeaders?.();

    let buffer = '';
    let clientClosed = false;

    const writeSse = (payload) => {
      if (!clientClosed) {
        res.write(`data: ${JSON.stringify(payload)}\n\n`);
      }
    };

    upstream.data.on('data', (chunk) => {
      buffer += chunk.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith('data:')) {
          continue;
        }

        const payload = trimmed.slice(5).trim();
        if (payload === '[DONE]') {
          writeSse({ done: true });
          res.end();
          return;
        }

        try {
          const parsed = JSON.parse(payload);
          const token = parsed?.choices?.[0]?.delta?.content || parsed?.choices?.[0]?.text || '';
          if (token) {
            writeSse({ token, done: false });
          }

          if (parsed?.choices?.[0]?.finish_reason) {
            writeSse({ done: true });
            res.end();
            return;
          }
        } catch {
          writeSse({ token: payload, done: false });
        }
      }
    });

    upstream.data.on('end', () => {
      if (!clientClosed && !res.writableEnded) {
        writeSse({ done: true });
        res.end();
      }
    });

    upstream.data.on('error', (error) => {
      if (!clientClosed) {
        next(error);
      }
    });

    req.on('close', () => {
      clientClosed = true;
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
