const express = require('express');

const llmController = require('../controllers/llmController');
const { validate } = require('../middleware/validate');

const router = express.Router();

router.post('/chat', validate.chatRequest, llmController.chat);
router.post('/stream', validate.chatRequest, llmController.stream);
router.get('/health', llmController.health);
router.get('/models', llmController.models);

module.exports = router;
