const fs = require('fs/promises');
const fsSync = require('fs');
const { spawn } = require('child_process');
const path = require('path');
const runtime = require('../config/runtime');

const whisperBin = path.resolve(process.env.WHISPER_BIN || runtime.stt.whisperBin || '/usr/bin/whisper-cli');
const whisperModel = path.resolve(process.env.WHISPER_MODEL || runtime.stt.whisperModel || '/usr/share/models/ggml-tiny.en.bin');

function runWhisper(args, timeoutMs) {
  return new Promise((resolve, reject) => {
    const child = spawn(whisperBin, args);
    let stderr = '';
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGKILL');
    }, timeoutMs);

    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    child.on('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });

    child.on('close', (code) => {
      clearTimeout(timer);
      if (timedOut) {
        reject(new Error('whisper-cli timed out'));
        return;
      }

      if (code !== 0) {
        reject(new Error(`whisper-cli failed with code ${code}: ${stderr}`));
        return;
      }

      resolve();
    });
  });
}

async function transcribe(wavFilePath) {
  const resolvedWavPath = path.resolve(wavFilePath);
  const outputBase = `${runtime.stt.outputPrefix}_${Date.now()}`;
  const outputTextPath = `${outputBase}.txt`;

  await fs.mkdir(path.dirname(outputBase), { recursive: true });

  try {
    await runWhisper(
      ['-m', whisperModel, '-f', resolvedWavPath, '-otxt', '-of', outputBase],
      runtime.stt.timeoutMs
    );

    const text = await fs.readFile(outputTextPath, 'utf8');
    return text.trim();
  } finally {
    await Promise.allSettled([
      fs.unlink(outputTextPath),
      fs.unlink(resolvedWavPath),
    ]);
  }
}

async function ping() {
  const binary = fsSync.existsSync(whisperBin);
  const model = fsSync.existsSync(whisperModel);

  return {
    ok: binary && model,
    binary,
    model,
  };
}

module.exports = {
  transcribe,
  ping,
};
