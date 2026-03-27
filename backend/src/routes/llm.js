const express = require('express');

const llmController = require('../controllers/llmController');

const router = express.Router();

router.post('/chat', llmController.chat);
router.post('/stream', llmController.stream);
router.get('/health', llmController.health);
router.get('/models', llmController.models);

module.exports = router;
