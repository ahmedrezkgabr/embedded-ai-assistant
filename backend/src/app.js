const path = require('path');
const express = require('express');
const cors = require('cors');
const morgan = require('morgan');

const requestId = require('./middleware/requestId');
const errorHandler = require('./middleware/errorHandler');
const llmRoutes = require('./routes/llm');
const voiceRoutes = require('./routes/voice');

const app = express();

app.use(cors());
app.use(morgan('combined'));
app.use(express.json({ limit: '2mb' }));
app.use(requestId);
app.use(express.static(path.join(__dirname, '..', 'public')));

app.use('/api/llm', llmRoutes);
app.use('/api/voice', voiceRoutes);

app.use(errorHandler);

module.exports = app;
