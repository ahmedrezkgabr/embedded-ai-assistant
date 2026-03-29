const { describe, test, expect, beforeEach } = require('@jest/globals');
const EventEmitter = require('events');

jest.mock('child_process', () => ({
  spawn: jest.fn(),
}));

jest.mock('fs/promises', () => ({
  mkdir: jest.fn(),
  readFile: jest.fn(),
  unlink: jest.fn(),
}));

jest.mock('fs', () => ({
  existsSync: jest.fn(),
}));

process.env.PIPER_BIN = '/tmp/piper';
process.env.PIPER_VOICE = '/tmp/voice.onnx';

const { spawn } = require('child_process');
const fs = require('fs/promises');
const fsSync = require('fs');
const ttsService = require('../../src/services/ttsService');

function createSpawnedProcess(exitCode = 0) {
  const child = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { write: jest.fn(), end: jest.fn() };

  process.nextTick(() => {
    child.emit('close', exitCode);
  });

  return child;
}

describe('ttsService', () => {
  beforeEach(() => {
    spawn.mockReset();
    fs.readFile.mockReset();
    fs.mkdir.mockReset();
    fs.unlink.mockReset();
    fsSync.existsSync.mockReset();
    fs.mkdir.mockResolvedValue(undefined);
    fs.unlink.mockResolvedValue(undefined);
  });

  test('synthesize() returns audio buffer', async () => {
    spawn.mockImplementation(() => createSpawnedProcess(0));
    fs.readFile.mockResolvedValue(Buffer.from('wav-data'));

    const result = await ttsService.synthesize('hello');

    expect(Buffer.isBuffer(result)).toBe(true);
    expect(spawn).toHaveBeenCalledWith(
      '/tmp/piper',
      expect.any(Array)
    );
    expect(fs.readFile).toHaveBeenCalledWith(expect.stringMatching(/\.wav$/));
  });

  test('synthesize() throws when piper exits non-zero', async () => {
    spawn.mockImplementation(() => createSpawnedProcess(1));

    await expect(ttsService.synthesize('hello')).rejects.toThrow(/piper failed/);
  });

  test('ping() reports binary/model readiness', async () => {
    fsSync.existsSync.mockReturnValue(true);

    const result = await ttsService.ping();

    expect(result).toEqual({ ok: true, binary: true, model: true, model_json: true });
  });
});
