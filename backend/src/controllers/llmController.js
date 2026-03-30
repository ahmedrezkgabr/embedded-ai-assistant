const llmService = require('../services/llmService');
const ttsService = require('../services/ttsService');

function createSentenceExtractor(onSentence) {
  let sentenceBuffer = '';

  const flush = () => {
    const remaining = sentenceBuffer.trim();
    if (remaining) {
      onSentence(remaining);
    }
    sentenceBuffer = '';
  };

  const push = (chunk) => {
    const piece = String(chunk || '');
    if (!piece) {
      return;
    }

    sentenceBuffer += piece;

    const parts = sentenceBuffer.split(/(?<=[.!?])\s+/);
    if (parts.length <= 1) {
      return;
    }

    sentenceBuffer = parts.pop() || '';
    for (const sentence of parts) {
      const trimmed = sentence.trim();
      if (trimmed) {
        onSentence(trimmed);
      }
    }
  };

  return { push, flush };
}

function parseSseFrames(buffer) {
  const frames = buffer.split('\n\n');
  const remainder = frames.pop() || '';
  return { frames, remainder };
}

function parseChatCompletionDelta(frame) {
  const dataLine = frame
    .split('\n')
    .find((line) => line.startsWith('data:'));

  if (!dataLine) {
    return { done: false, token: '' };
  }

  const payload = dataLine.slice(5).trim();
  if (!payload) {
    return { done: false, token: '' };
  }

  if (payload === '[DONE]') {
    return { done: true, token: '' };
  }

  try {
    const parsed = JSON.parse(payload);
    const token = parsed?.choices?.[0]?.delta?.content || '';
    return { done: false, token };
  } catch {
    return { done: false, token: '' };
  }
}

function normalizeAsciiToken(token) {
  return String(token || '')
    .replace(/[^\x20-\x7E\n\r\t]/g, '')
    .replace(/[ \t]+/g, ' ')
    .trim();
}

async function chat(req, res, next) {
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
      duration_ms: result.duration_ms,
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
    const enableTtsStream = Boolean(req.body?.tts_stream);
    const ttsVoice = req.body?.voice;
    const options = {
      ...(req.body?.options || {}),
      ...(req.body?.temperature !== undefined ? { temperature: req.body.temperature } : {}),
      ...(req.body?.max_tokens !== undefined ? { max_tokens: req.body.max_tokens } : {}),
    };

    let closed = false;
    const pendingTts = [];
    let ttsActive = false;

    const abortController = new AbortController();
    const streamResponse = await llmService.streamChat(prompt, model, {
      ...options,
      signal: abortController.signal,
    });

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');
    if (typeof res.flushHeaders === 'function') {
      res.flushHeaders();
    }

    const sendSse = (payload, eventName) => {
      if (closed || res.writableEnded) {
        return;
      }
      if (eventName) {
        res.write(`event: ${eventName}\n`);
      }
      res.write(`data: ${JSON.stringify(payload)}\n\n`);
    };

    const runTtsQueue = async () => {
      if (ttsActive) {
        return;
      }

      ttsActive = true;
      while (!closed && pendingTts.length > 0) {
        const sentence = pendingTts.shift();
        if (!sentence) {
          continue;
        }

        try {
          const audio = await ttsService.synthesize(sentence, ttsVoice);
          sendSse(
            {
              type: 'audio',
              sentence,
              mime: 'audio/wav',
              audio_base64: audio.toString('base64'),
            },
            'audio'
          );
        } catch (error) {
          sendSse({
            type: 'audio_error',
            sentence,
            error: error.message,
          }, 'audio_error');
        }
      }
      ttsActive = false;
    };

    const sentenceExtractor = createSentenceExtractor((sentence) => {
      sendSse({ type: 'sentence', sentence }, 'sentence');
      if (enableTtsStream) {
        pendingTts.push(sentence);
        runTtsQueue();
      }
    });

    const sendDone = () => {
      if (closed || res.writableEnded) {
        return;
      }
      sendSse({ done: true }, 'done');
      res.end();
      closed = true;
    };

    let buffer = '';

    streamResponse.data.on('data', (chunk) => {
      if (closed) {
        return;
      }

      buffer += chunk.toString('utf8');
      const parsed = parseSseFrames(buffer);
      buffer = parsed.remainder;

      for (const frame of parsed.frames) {
        const delta = parseChatCompletionDelta(frame);
        const normalizedToken = normalizeAsciiToken(delta.token);
        if (normalizedToken) {
          sendSse({ token: normalizedToken, done: false }, 'token');
          sentenceExtractor.push(normalizedToken);
        }
        if (delta.done) {
          sentenceExtractor.flush();
          sendDone();
          return;
        }
      }
    });

    streamResponse.data.on('end', () => {
      if (!closed) {
        sentenceExtractor.flush();
        sendDone();
      }
    });

    streamResponse.data.on('error', (error) => {
      if (!closed) {
        sendSse({ error: error.message }, 'error');
        sendDone();
      }
    });

    req.on('close', () => {
      closed = true;
      abortController.abort();
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
    return res.json({ data, requestId: req.requestId });
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
