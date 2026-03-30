require('dotenv').config();

const app = require('./app');
const runtime = require('./config/runtime');

process.on('unhandledRejection', (reason) => {
  process.stderr.write(`Unhandled rejection: ${String(reason)}\n`);
});

process.on('uncaughtException', (error) => {
  process.stderr.write(`Uncaught exception: ${error.stack || String(error)}\n`);
});

const port = runtime.server.port;

app.listen(port, () => {
  process.stdout.write(`AI assistant backend listening on port ${port}\n`);
});
