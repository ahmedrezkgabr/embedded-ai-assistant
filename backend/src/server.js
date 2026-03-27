require('dotenv').config();

const app = require('./app');

const port = Number(process.env.PORT || 3000);

app.listen(port, () => {
  process.stdout.write(`AI assistant backend listening on port ${port}\n`);
});
