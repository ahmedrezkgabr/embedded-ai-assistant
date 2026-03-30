const { describe, test, expect } = require('@jest/globals');

jest.mock('../../src/services/llmService', () => ({
  chat: jest.fn(),
  streamChat: jest.fn(),
  ping: jest.fn(),
  listModels: jest.fn(),
}));

jest.mock('../../src/services/ttsService', () => ({
  synthesize: jest.fn(),
}));

const llmController = require('../../src/controllers/llmController');

describe('llmController.__private.normalizeAsciiToken', () => {
  test('preserves leading spaces needed between streamed words', () => {
    const normalized = llmController.__private.normalizeAsciiToken(' world');

    expect(normalized).toBe(' world');
  });

  test('removes non-ascii characters but keeps spacing', () => {
    const normalized = llmController.__private.normalizeAsciiToken('  héllo\tworld  ');

    expect(normalized).toBe(' hllo world ');
  });
});
