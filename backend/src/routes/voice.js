const express = require('express');
const multer = require('multer');

const voiceController = require('../controllers/voiceController');
const { validate } = require('../middleware/validate');

const router = express.Router();
const upload = multer({ dest: 'uploads/' });

router.post('/stt', upload.single('audio'), voiceController.speechToText);
router.post('/tts', validate.ttsRequest, voiceController.textToSpeech);
router.get('/health', voiceController.health);

module.exports = router;
