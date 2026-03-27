const fs = require('fs/promises');
const { constants } = require('fs');
const { spawn } = require('child_process');

const whisperBin = process.env.WHISPER_BIN || '/usr/local/bin/whisper-cli';
const whisperModel = process.env.WHISPER_MODEL || '/opt/ai-assistant/models/ggml-tiny.en.bin';

function runWithTimeout(command, args, timeoutMs) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args);
    let stderr = '';
    let didTimeout = false;

    const timer = setTimeout(() => {
      didTimeout = true;
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
      if (didTimeout) {
        return reject(new Error('whisper-cli timed out'));
      }
      if (code !== 0) {
        return reject(new Error(`whisper-cli failed with code ${code}: ${stderr}`));
      }
      return resolve();
    });
  });
}

async function transcribe(wavFilePath) {
  const outputBase = `/tmp/whisper_out_${Date.now()}`;

  try {
    await runWithTimeout(
      whisperBin,
      ['-m', whisperModel, '-f', wavFilePath, '-otxt', '-of', outputBase],
      30000
    );

    const outputText = await fs.readFile(`${outputBase}.txt`, 'utf8');
    return outputText.trim();
  } finally {
    await Promise.allSettled([
      fs.unlink(wavFilePath),
      fs.unlink(`${outputBase}.txt`),
    ]);
  }
}

async function ping() {
  let binary = false;
  let model = false;

  try {
    await fs.access(whisperBin, constants.X_OK);
    binary = true;
  } catch {
    binary = false;
  }

  try {
    await fs.access(whisperModel, constants.R_OK);
    model = true;
  } catch {
    model = false;
  }

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
