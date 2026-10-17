const { validatePayment } = require('../src/payments');

describe('validatePayment', () => {
  test('accepts a valid payment', () => {
    expect(validatePayment({ amount: 500, phone: '254712345678' }).valid).toBe(true);
  });

  test('rejects a zero amount', () => {
    expect(validatePayment({ amount: 0, phone: '254712345678' }).valid).toBe(false);
  });

  test('rejects a decimal amount', () => {
    expect(validatePayment({ amount: 10.5, phone: '254712345678' }).valid).toBe(false);
  });

  test('rejects a badly formatted phone number', () => {
    expect(validatePayment({ amount: 500, phone: '0712345678' }).valid).toBe(false);
  });

  test('rejects a missing body', () => {
    expect(validatePayment(undefined).valid).toBe(false);
  });
});
