require('dotenv').config();

const app = require('./app');
const runtime = require('./config/runtime');

const port = runtime.server.port;

app.listen(port, () => {
  process.stdout.write(`AI assistant backend listening on port ${port}\n`);
});
