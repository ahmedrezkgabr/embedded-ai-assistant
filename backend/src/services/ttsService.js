const fs = require('fs/promises');
const fsSync = require('fs');
const { spawn } = require('child_process');
const path = require('path');
const crypto = require('crypto');
const runtime = require('../config/runtime');

const piperBin = path.resolve(process.env.PIPER_BIN || runtime.tts.piperBin || '/usr/bin/piper');
const defaultVoice = path.resolve(process.env.PIPER_VOICE || runtime.tts.defaultVoice || '/usr/share/models/en_US-lessac-low.onnx');
const espeakData = process.env.PIPER_ESPEAK_DATA || runtime.tts.espeakData || '';

function resolveVoicePath(voiceName) {
  if (!voiceName) {
    return defaultVoice;
  }

  if (voiceName.endsWith('.onnx') || path.isAbsolute(voiceName)) {
    return path.resolve(voiceName);
  }

  const voiceDir = path.resolve(process.env.PIPER_VOICE_DIR || runtime.tts.voiceDir || '/usr/share/models');
  return path.resolve(path.join(voiceDir, `${voiceName}.onnx`));
}

function runPiper(modelPath, outputFile, text) {
  return new Promise((resolve, reject) => {
    const args = ['--model', modelPath, '--output_file', outputFile];

    if (espeakData) {
      args.push('--espeak_data', path.resolve(espeakData));
    }

    const child = spawn(piperBin, args);
    let stderr = '';
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
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
      if (timedOut) {
        reject(new Error('piper timed out'));
        return;
      }

      if (code !== 0) {
        reject(new Error(`piper failed with code ${code}: ${stderr}`));
        return;
      }

      resolve();
    });

    child.stdin.write(String(text));
    child.stdin.end();
  });
}

async function synthesize(text, voiceName) {
  const outputFile = `${runtime.tts.outputPrefix}_${crypto.randomUUID()}.wav`;
  const modelPath = resolveVoicePath(voiceName);

  await fs.mkdir(path.dirname(outputFile), { recursive: true });

  try {
    await runPiper(modelPath, outputFile, text);
    const buffer = await fs.readFile(outputFile);

    if (buffer.length <= 44) {
      throw new Error('TTS produced empty audio');
    }

    return buffer;
  } finally {
    await fs.unlink(outputFile).catch(() => {});
  }
}

async function ping() {
  const voicePath = resolveVoicePath();
  const binary = fsSync.existsSync(piperBin);
  const model = fsSync.existsSync(voicePath);
  const modelJson = fsSync.existsSync(`${voicePath}.json`);

  return {
    ok: binary && model && modelJson,
    binary,
    model,
    model_json: modelJson,
  };
}

module.exports = {
  synthesize,
  ping,
};
