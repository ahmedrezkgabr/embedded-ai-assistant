const { body, validationResult } = require('express-validator');

const ttsRequest = [
  body('text').isString().trim().notEmpty().isLength({ max: 1000 }),
  body('voice').optional().isString().trim().isLength({ min: 1, max: 200 }),
  (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'invalid request', details: errors.array(), requestId: req.requestId });
    }
    return next();
  },
];

const validate = {
  ttsRequest,
};

module.exports = {
  validate,
};
