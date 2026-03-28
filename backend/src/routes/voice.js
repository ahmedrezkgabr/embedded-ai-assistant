const express = require('express');
const multer = require('multer');
const fs = require('fs');

const voiceController = require('../controllers/voiceController');
const { validate } = require('../middleware/validate');
const runtime = require('../config/runtime');

const router = express.Router();

fs.mkdirSync(runtime.uploads.dir, { recursive: true });
const upload = multer({ dest: runtime.uploads.dir });

router.post('/stt', upload.single('audio'), voiceController.speechToText);
router.post('/tts', validate.ttsRequest, voiceController.textToSpeech);
router.get('/health', voiceController.health);

module.exports = router;
