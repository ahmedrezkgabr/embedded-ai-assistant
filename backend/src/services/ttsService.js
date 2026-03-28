const fs = require('fs/promises');
const { constants } = require('fs');
const { spawn } = require('child_process');
const path = require('path');
const runtime = require('../config/runtime');

const piperBin = runtime.tts.piperBin;
const defaultVoice = runtime.tts.defaultVoice;

function resolveVoicePath(voiceName) {
  if (!voiceName) {
    return defaultVoice;
  }

  if (voiceName.endsWith('.onnx') || voiceName.startsWith('/')) {
    return voiceName;
  }

  return path.join(runtime.tts.voiceDir, `${voiceName}.onnx`);
}

async function synthesize(text, voiceName) {
  if (typeof fs.mkdir === 'function') {
    await fs.mkdir(path.dirname(runtime.tts.outputPrefix), { recursive: true });
  }
  const outputFile = `${runtime.tts.outputPrefix}_${Date.now()}.wav`;
  const modelPath = resolveVoicePath(voiceName);

  try {
    await new Promise((resolve, reject) => {
      const child = spawn(piperBin, ['--model', modelPath, '--output_file', outputFile]);
      let stderr = '';
      let didTimeout = false;

      const timer = setTimeout(() => {
        didTimeout = true;
        child.kill('SIGKILL');
      }, runtime.tts.timeoutMs);

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
          return reject(new Error('piper timed out'));
        }
        if (code !== 0) {
          return reject(new Error(`piper failed with code ${code}: ${stderr}`));
        }
        return resolve();
      });

      child.stdin.write(text);
      child.stdin.end();
    });

    return fs.readFile(outputFile);
  } finally {
    await fs.unlink(outputFile).catch(() => {});
  }
}

async function ping() {
  let binary = false;
  let model = false;

  try {
    await fs.access(piperBin, constants.X_OK);
    binary = true;
  } catch {
    binary = false;
  }

  try {
    await fs.access(defaultVoice, constants.R_OK);
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
  synthesize,
  ping,
};
