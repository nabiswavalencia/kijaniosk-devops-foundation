const express = require('express');
const { validatePayment } = require('./payments');

// The image build sets APP_VERSION to the full image tag (<semver>-<git-sha>),
// so /health reports exactly which build is running. Outside a container it
// falls back to the package.json version.
const APP_VERSION = process.env.APP_VERSION || require('../package.json').version;

const app = express();
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'kk-payments', version: APP_VERSION });
});

app.post('/payments', (req, res) => {
  const result = validatePayment(req.body);
  if (!result.valid) {
    return res.status(400).json({ errors: result.errors });
  }
  return res.status(202).json({ status: 'accepted', amount: req.body.amount });
});

module.exports = app;
