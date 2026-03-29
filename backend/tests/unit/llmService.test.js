const { describe, test, expect, beforeEach } = require('@jest/globals');

jest.mock('axios', () => ({
  create: jest.fn(),
}));

process.env.LLM_BASE_URL = 'http://localhost:11434';
process.env.LLM_DEFAULT_MODEL = 'test-model';
process.env.LLM_TIMEOUT = '60000';

const axios = require('axios');
const mockClient = {
  post: jest.fn(),
  get: jest.fn(),
};

axios.create.mockReturnValue(mockClient);

const llmService = require('../../src/services/llmService');

describe('llmService', () => {
  beforeEach(() => {
    mockClient.post.mockReset();
    mockClient.get.mockReset();
  });

  test('chat() returns response and model', async () => {
    mockClient.post.mockResolvedValue({
      data: {
        model: 'test-model',
        choices: [{ message: { content: 'PONG' } }],
      },
    });

    const result = await llmService.chat('ping');

    expect(result).toEqual(expect.objectContaining({ response: 'PONG', model: 'test-model' }));
    expect(result.duration_ms).toBeGreaterThanOrEqual(0);
    expect(mockClient.post).toHaveBeenCalledWith(
      '/v1/chat/completions',
      expect.objectContaining({ stream: false })
    );
  });

  test('ping() returns ok=true when health endpoint is reachable', async () => {
    mockClient.get.mockResolvedValue({ data: { status: 'ok' } });

    const result = await llmService.ping();

    expect(result.ok).toBe(true);
    expect(result.status).toBe('ok');
    expect(result.latency_ms).toBeGreaterThanOrEqual(0);
    expect(mockClient.get).toHaveBeenCalledWith('/health');
  });

  test('listModels() returns models array', async () => {
    mockClient.get.mockResolvedValue({
      data: {
        data: [{ id: 'model-1' }, { id: 'model-2' }],
      },
    });

    const result = await llmService.listModels();

    expect(result).toEqual([{ id: 'model-1' }, { id: 'model-2' }]);
    expect(mockClient.get).toHaveBeenCalledWith('/v1/models');
  });
});
