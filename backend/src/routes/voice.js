const express = require('express');
const multer = require('multer');
const fs = require('fs');

const voiceController = require('../controllers/voiceController');
const { validate } = require('../middleware/validate');
const runtime = require('../config/runtime');

const router = express.Router();

fs.mkdirSync(runtime.uploads.dir, { recursive: true });

const ALLOWED_MIME_TYPES = new Set([
  'audio/wav',
  'audio/wave',
  'audio/x-wav',
  'audio/webm',
  'audio/ogg',
]);

const upload = multer({
  dest: runtime.uploads.dir,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (ALLOWED_MIME_TYPES.has(file.mimetype)) {
      cb(null, true);
    } else {
      const err = new Error('Only audio files (wav, webm, ogg) are accepted');
      err.status = 400;
      cb(err, false);
    }
  },
});

router.post('/stt', upload.single('audio'), voiceController.speechToText);
router.post('/tts', validate.ttsRequest, voiceController.textToSpeech);
router.get('/health', voiceController.health);

module.exports = router;
