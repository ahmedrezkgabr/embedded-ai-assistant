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

process.env.WHISPER_BIN = '/tmp/whisper-cli';
process.env.WHISPER_MODEL = '/tmp/model.bin';

const { spawn } = require('child_process');
const fs = require('fs/promises');
const fsSync = require('fs');
const sttService = require('../../src/services/sttService');

function createSpawnedProcess(exitCode = 0) {
  const child = new EventEmitter();
  child.stderr = new EventEmitter();

  process.nextTick(() => {
    child.emit('close', exitCode);
  });

  return child;
}

describe('sttService', () => {
  beforeEach(() => {
    spawn.mockReset();
    fs.readFile.mockReset();
    fs.mkdir.mockReset();
    fs.unlink.mockReset();
    fsSync.existsSync.mockReset();
    fs.mkdir.mockResolvedValue(undefined);
    fs.unlink.mockResolvedValue(undefined);
  });

  test('transcribe() returns trimmed transcript', async () => {
    spawn.mockImplementation(() => createSpawnedProcess(0));
    fs.readFile.mockResolvedValue('  hello world  \n');

    const transcript = await sttService.transcribe('/tmp/test.wav');

    expect(transcript).toBe('hello world');
    expect(spawn).toHaveBeenCalledWith('/tmp/whisper-cli', expect.any(Array));
  });

  test('transcribe() throws when whisper exits non-zero', async () => {
    spawn.mockImplementation(() => createSpawnedProcess(1));

    await expect(sttService.transcribe('/tmp/test.wav')).rejects.toThrow(/whisper-cli failed/);
  });

  test('ping() reports binary/model readiness', async () => {
    fsSync.existsSync.mockReturnValue(true);

    const result = await sttService.ping();

    expect(result).toEqual({ ok: true, binary: true, model: true });
  });
});
