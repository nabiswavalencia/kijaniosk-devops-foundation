const express = require('express');
const { validatePayment } = require('./payments');

const app = express();
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'kk-payments' });
});

app.post('/payments', (req, res) => {
  const result = validatePayment(req.body);
  if (!result.valid) {
    return res.status(400).json({ errors: result.errors });
  }
  return res.status(202).json({ status: 'accepted', amount: req.body.amount });
});

module.exports = app;
