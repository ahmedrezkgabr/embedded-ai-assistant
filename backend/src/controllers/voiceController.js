const sttService = require('../services/sttService');
const ttsService = require('../services/ttsService');

async function speechToText(req, res, next) {
  const started = Date.now();
  try {
    if (!req.file?.path) {
      return res.status(400).json({ error: 'audio file is required', requestId: req.requestId });
    }

    const transcript = await sttService.transcribe(req.file.path);
    return res.json({ transcript, duration_ms: Date.now() - started, requestId: req.requestId });
  } catch (error) {
    return next(error);
  }
}

async function textToSpeech(req, res, next) {
  try {
    const text = String(req.body?.text || '').trim();
    const voice = req.body?.voice;

    if (!text) {
      return res.status(400).json({ error: 'text is required', requestId: req.requestId });
    }

    const audioBuffer = await ttsService.synthesize(text, voice);
    res.setHeader('Content-Type', 'audio/wav');
    res.setHeader('Content-Length', audioBuffer.length);
    return res.send(audioBuffer);
  } catch (error) {
    return next(error);
  }
}

async function health(req, res, next) {
  try {
    const stt = await sttService.ping();
    const tts = await ttsService.ping();
    return res.json({ stt, tts, requestId: req.requestId });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  speechToText,
  textToSpeech,
  health,
};
