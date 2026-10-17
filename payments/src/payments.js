const PHONE_PATTERN = /^2547\d{8}$/;

function validatePayment(payment) {
  const errors = [];
  if (!payment || typeof payment !== 'object') {
    return { valid: false, errors: ['payment body is required'] };
  }
  if (!Number.isInteger(payment.amount) || payment.amount <= 0) {
    errors.push('amount must be a positive whole number of KES');
  }
  if (!PHONE_PATTERN.test(String(payment.phone))) {
    errors.push('phone must be in the format 2547XXXXXXXX');
  }
  return { valid: errors.length === 0, errors };
}

module.exports = { validatePayment };
const broken = ;
