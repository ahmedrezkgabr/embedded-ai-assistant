function errorHandler(error, req, res, next) {
  if (res.headersSent) {
    return next(error);
  }

  const status = error.status || error.statusCode || 500;
  const message = status >= 500 ? 'Internal Server Error' : error.message;

  return res.status(status).json({
    error: message,
    requestId: req.requestId,
  });
}

module.exports = errorHandler;
