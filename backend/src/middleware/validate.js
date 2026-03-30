const { body, validationResult } = require('express-validator');

const handleValidation = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ error: 'invalid request', details: errors.array(), requestId: req.requestId });
  }
  return next();
};

const ttsRequest = [
  body('text').isString().trim().notEmpty().isLength({ max: 1000 }),
  body('voice').optional().isString().trim().isLength({ min: 1, max: 200 }),
  handleValidation,
];

const chatRequest = [
  body('prompt').isString().trim().notEmpty().withMessage('prompt is required'),
  body('model').optional().isString().trim().isLength({ min: 1, max: 200 }),
  body('options.temperature').optional().isFloat({ min: 0, max: 2 }).toFloat(),
  body('options.max_tokens').optional().isInt({ min: 1, max: 2048 }).toInt(),
  body('options.system_prompt').optional().isString().isLength({ max: 2000 }),
  body('temperature').optional().isFloat({ min: 0, max: 2 }).toFloat(),
  body('max_tokens').optional().isInt({ min: 1, max: 2048 }).toInt(),
  handleValidation,
];

const validate = {
  ttsRequest,
  chatRequest,
};

module.exports = {
  validate,
};
