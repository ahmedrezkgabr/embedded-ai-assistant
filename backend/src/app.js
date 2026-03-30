const path = require('path');
const fs = require('fs');
const express = require('express');
const cors = require('cors');
const morgan = require('morgan');

const requestId = require('./middleware/requestId');
const errorHandler = require('./middleware/errorHandler');
const llmRoutes = require('./routes/llm');
const voiceRoutes = require('./routes/voice');
const runtime = require('./config/runtime');

const app = express();

const logDir = path.dirname(runtime.server.logFile);
fs.mkdirSync(logDir, { recursive: true });

const logStream = fs.createWriteStream(runtime.server.logFile, { flags: 'a' });

const allowedOrigins = (process.env.CORS_ORIGINS || '').split(',').filter(Boolean);

app.use(cors({
  origin: (origin, callback) => {
    if (!origin) {
      return callback(null, true);
    }
    if (allowedOrigins.length > 0 && allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    if (/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
      return callback(null, true);
    }
    if (/^https?:\/\/(10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|192\.168\.\d+\.\d+)(:\d+)?$/.test(origin)) {
      return callback(null, true);
    }
    return callback(new Error('CORS not allowed'), false);
  },
}));
app.use(morgan('combined', { stream: logStream }));
app.use(express.json({ limit: '2mb' }));
app.use(requestId);
app.use(express.static(path.join(__dirname, '..', 'public')));

app.use('/api/llm', llmRoutes);
app.use('/api/voice', voiceRoutes);

app.use(errorHandler);

module.exports = app;
