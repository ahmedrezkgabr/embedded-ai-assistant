const { describe, test, expect } = require('@jest/globals');
const { validate } = require('../../src/middleware/validate');

async function runMiddlewareChain(middlewares, req) {
  const res = {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };

  let nextCalled = false;
  const next = () => {
    nextCalled = true;
  };

  for (const middleware of middlewares) {
    await middleware(req, res, next);
  }

  return { res, nextCalled };
}

describe('validate.ttsRequest', () => {
  test('rejects missing text', async () => {
    const req = { body: {}, requestId: 'req-1' };
    const { res } = await runMiddlewareChain(validate.ttsRequest, req);

    expect(res.statusCode).toBe(400);
    expect(res.body.error).toBe('invalid request');
  });

  test('accepts valid text and optional voice', async () => {
    const req = { body: { text: 'hello', voice: 'en_US-lessac-low' }, requestId: 'req-2' };
    const { res, nextCalled } = await runMiddlewareChain(validate.ttsRequest, req);

    expect(nextCalled).toBe(true);
    expect(res.statusCode).toBe(200);
  });
});
