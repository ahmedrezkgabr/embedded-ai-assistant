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

app.use(cors());
app.use(morgan('combined', { stream: logStream }));
app.use(express.json({ limit: '2mb' }));
app.use(requestId);
app.use(express.static(path.join(__dirname, '..', 'public')));

app.use('/api/llm', llmRoutes);
app.use('/api/voice', voiceRoutes);

app.use(errorHandler);

module.exports = app;
