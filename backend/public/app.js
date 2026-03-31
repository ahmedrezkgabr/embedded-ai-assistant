const state = {
  mediaRecorder: null,
  audioStream: null,
  recordedChunks: [],
  isRecording: false,
  isBusy: false,
  isTTSEnabled: true,
  currentModel: '',
  settings: {
    temperature: 0,
    max_tokens: 128,
    systemPrompt: 'You are a helpful assistant.',
    voice: 'en_US-lessac-low',
  },
  waveform: {
    context: null,
    analyser: null,
    source: null,
    frameId: null,
  },
};

const chatWindow = document.getElementById('chat-window');
const chatEmptyState = document.getElementById('chat-empty-state');
const promptInput = document.getElementById('prompt-input');
const sendBtn = document.getElementById('send-btn');
const clearBtn = document.getElementById('clear-btn');
const micBtn = document.getElementById('mic-btn');
const micStatus = document.getElementById('mic-status');
const waveformCanvas = document.getElementById('waveform');
const ttsToggle = document.getElementById('tts-toggle');
const modelSelect = document.getElementById('model-select');
const voiceSelect = document.getElementById('voice-select');
const settingsToggleBtn = document.getElementById('settings-toggle');
const settingsDialog = document.getElementById('settings-dialog');
const settingsCloseBtn = document.getElementById('settings-close');

const temperatureInput = document.getElementById('temperature');
const temperatureValue = document.getElementById('temperature-value');
const maxTokensInput = document.getElementById('max-tokens');
const systemPromptInput = document.getElementById('system-prompt');

const llmDot = document.getElementById('llm-dot');
const sttDot = document.getElementById('stt-dot');
const ttsDot = document.getElementById('tts-dot');

const ICONS = {
  mic: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 15a4 4 0 0 0 4-4V7a4 4 0 1 0-8 0v4a4 4 0 0 0 4 4Zm-1 3.93V22h2v-3.07A7 7 0 0 0 19 12h-2a5 5 0 1 1-10 0H5a7 7 0 0 0 6 6.93Z"/></svg>',
  send: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 3 3 10.53V12l7 2 2 7h1.47L21 3Z"/></svg>',
  stop: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 7h10v10H7z"/></svg>',
  spinner: '<svg class="spin" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2" opacity="0.25"></circle><path d="M21 12a9 9 0 0 0-9-9" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"></path></svg>',
};

function setButtonIcon(button, iconName) {
  button.innerHTML = ICONS[iconName] || '';
}

function renderActionButtons() {
  const micIcon = state.isBusy ? 'spinner' : state.isRecording ? 'stop' : 'mic';
  const sendIcon = state.isBusy ? 'spinner' : 'send';

  setButtonIcon(micBtn, micIcon);
  setButtonIcon(sendBtn, sendIcon);

  micBtn.classList.toggle('loading', state.isBusy);
  sendBtn.classList.toggle('loading', state.isBusy);

  micBtn.disabled = state.isBusy;
  sendBtn.disabled = state.isBusy || state.isRecording;
}

function setBusyState(isBusy, statusText) {
  state.isBusy = isBusy;
  if (statusText) {
    micStatus.textContent = statusText;
  }
  renderActionButtons();
}

function resizePromptInput() {
  promptInput.style.height = 'auto';
  promptInput.style.height = `${Math.min(promptInput.scrollHeight, 140)}px`;
}

function setDot(dot, ok) {
  dot.classList.toggle('ok', ok);
  dot.classList.toggle('err', !ok);
}

function appendMessage(role, text) {
  const wrap = document.createElement('div');
  wrap.className = `message ${role}`;

  const content = document.createElement('div');
  content.className = 'content';
  content.textContent = text;
  wrap.appendChild(content);

  if (role === 'assistant') {
    const actions = document.createElement('div');
    actions.className = 'assistant-actions';
    const btn = document.createElement('button');
    btn.className = 'play-btn';
    btn.type = 'button';
    btn.textContent = 'Play audio';
    btn.addEventListener('click', () => speakText(content.textContent));
    actions.appendChild(btn);
    wrap.appendChild(actions);
  }

  chatWindow.appendChild(wrap);
  chatWindow.scrollTop = chatWindow.scrollHeight;
  syncChatEmptyState();
  return { wrap, content };
}

function syncChatEmptyState() {
  if (!chatWindow || !chatEmptyState) {
    return;
  }
  const hasMessages = chatWindow.querySelector('.message') !== null;
  chatEmptyState.hidden = hasMessages;
}

async function sendTextMessage(text, options = {}) {
  const prompt = String(text || '').trim();
  if (!prompt) {
    return;
  }

  if (state.isBusy && !options.alreadyBusy) {
    return;
  }

  const ownsBusyState = !options.alreadyBusy;
  if (ownsBusyState) {
    setBusyState(true, 'Thinking...');
  }

  appendMessage('user', prompt);
  promptInput.value = '';
  resizePromptInput();

  const assistant = appendMessage('assistant', '');
  assistant.content.classList.add('typing-cursor');

  try {
    const response = await fetch('/api/llm/stream', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        prompt,
        model: state.currentModel,
        options: {
          temperature: state.settings.temperature,
          max_tokens: state.settings.max_tokens,
          system_prompt: state.settings.systemPrompt,
        },
      }),
    });

    if (!response.ok || !response.body) {
      throw new Error('Streaming request failed');
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }

      buffer += decoder.decode(value, { stream: true });
      const frames = buffer.split('\n\n');
      buffer = frames.pop() || '';

      for (const frame of frames) {
        const line = frame.split('\n').find((item) => item.startsWith('data:'));
        if (!line) {
          continue;
        }
        const payload = line.slice(5).trim();
        if (!payload) {
          continue;
        }

        let parsed;
        try {
          parsed = JSON.parse(payload);
        } catch {
          continue;
        }
        if (parsed.token) {
          assistant.content.textContent += parsed.token;
          chatWindow.scrollTop = chatWindow.scrollHeight;
        }
        if (parsed.done) {
          break;
        }
      }
    }

    assistant.content.classList.remove('typing-cursor');
    if (state.isTTSEnabled && assistant.content.textContent.trim()) {
      await speakText(assistant.content.textContent);
    }
  } catch (error) {
    assistant.content.classList.remove('typing-cursor');
    assistant.content.textContent = `Error: ${error.message}`;
  } finally {
    if (ownsBusyState) {
      setBusyState(false, state.isRecording ? 'Recording...' : 'Idle');
    }
  }
}

function chooseMimeType() {
  if (typeof MediaRecorder === 'undefined' || typeof MediaRecorder.isTypeSupported !== 'function') {
    return '';
  }

  const candidates = [
    'audio/webm;codecs=opus',
    'audio/webm',
    'audio/ogg;codecs=opus',
    'audio/mp4',
  ];
  for (const mime of candidates) {
    if (MediaRecorder.isTypeSupported(mime)) {
      return mime;
    }
  }
  return '';
}

function microphoneSupportMessage() {
  if (!window.isSecureContext) {
    return 'Microphone API unavailable in this context. Use HTTPS or http://localhost.';
  }
  return 'Microphone API is not supported by this browser.';
}

function getLegacyGetUserMedia() {
  return (
    navigator.getUserMedia
    || navigator.webkitGetUserMedia
    || navigator.mozGetUserMedia
    || navigator.msGetUserMedia
    || null
  );
}

async function requestMicrophoneStream() {
  if (navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function') {
    return navigator.mediaDevices.getUserMedia({ audio: true });
  }

  const legacyGetUserMedia = getLegacyGetUserMedia();
  if (legacyGetUserMedia) {
    return new Promise((resolve, reject) => {
      legacyGetUserMedia.call(navigator, { audio: true }, resolve, reject);
    });
  }

  throw new Error(microphoneSupportMessage());
}

async function startRecording() {
  if (state.isRecording) {
    return;
  }

  if (typeof MediaRecorder === 'undefined') {
    throw new Error('MediaRecorder is not supported by this browser.');
  }

  state.audioStream = await requestMicrophoneStream();
  state.recordedChunks = [];

  const mimeType = chooseMimeType();
  const options = mimeType ? { mimeType } : {};
  state.mediaRecorder = new MediaRecorder(state.audioStream, options);
  state.isRecording = true;

  setMicState('recording', 'Recording...');
  startWaveform();

  state.mediaRecorder.ondataavailable = (event) => {
    if (event.data.size > 0) {
      state.recordedChunks.push(event.data);
    }
  };

  state.mediaRecorder.onstop = async () => {
    try {
      setMicState('processing', 'Transcribing...');
      await processAudioToWAV(state.recordedChunks);
      setMicState('idle', 'Idle');
    } catch (error) {
      setMicState('idle', `Error: ${error.message}`);
    }
  };

  state.mediaRecorder.start(250);
  window.setTimeout(() => {
    if (state.isRecording) {
      stopRecording();
    }
  }, 30000);
}

function stopRecording() {
  if (!state.isRecording) {
    return;
  }

  state.isRecording = false;
  if (state.mediaRecorder?.state !== 'inactive') {
    state.mediaRecorder.stop();
  }

  if (state.audioStream) {
    for (const track of state.audioStream.getTracks()) {
      track.stop();
    }
  }

  stopWaveform();
}

async function processAudioToWAV(chunks) {
  setBusyState(true, 'Transcribing...');
  let audioContext;

  try {
    const mimeType = state.mediaRecorder?.mimeType || 'audio/webm;codecs=opus';
    const blob = new Blob(chunks, { type: mimeType });
    const inputBuffer = await blob.arrayBuffer();
    audioContext = new AudioContext();
    const decoded = await audioContext.decodeAudioData(inputBuffer.slice(0));

    const offlineContext = new OfflineAudioContext(1, Math.ceil(decoded.duration * 16000), 16000);
    const source = offlineContext.createBufferSource();
    const monoBuffer = offlineContext.createBuffer(1, decoded.length, decoded.sampleRate);

    const left = decoded.getChannelData(0);
    if (decoded.numberOfChannels > 1) {
      const right = decoded.getChannelData(1);
      const mixed = monoBuffer.getChannelData(0);
      for (let i = 0; i < mixed.length; i += 1) {
        mixed[i] = (left[i] + right[i]) * 0.5;
      }
    } else {
      monoBuffer.copyToChannel(left, 0);
    }

    source.buffer = monoBuffer;
    source.connect(offlineContext.destination);
    source.start(0);
    const rendered = await offlineContext.startRendering();
    const wavData = encodeWAV(rendered.getChannelData(0), 16000);

    const formData = new FormData();
    formData.append('audio', new Blob([wavData], { type: 'audio/wav' }), 'recording.wav');

    const response = await fetch('/api/voice/stt', {
      method: 'POST',
      body: formData,
    });

    if (!response.ok) {
      throw new Error('STT request failed');
    }

    const payload = await response.json();
    const transcript = String(payload.transcript || '').trim();
    promptInput.value = transcript;
    resizePromptInput();

    if (transcript.length > 2) {
      setMicState('processing', 'Thinking...');
      await sendTextMessage(transcript, { alreadyBusy: true });
    }
  } finally {
    if (audioContext) {
      await audioContext.close();
    }
    setBusyState(false, 'Idle');
  }
}

function encodeWAV(float32Array, sampleRate) {
  const bytesPerSample = 2;
  const dataLength = float32Array.length * bytesPerSample;
  const buffer = new ArrayBuffer(44 + dataLength);
  const view = new DataView(buffer);

  const writeString = (offset, text) => {
    for (let i = 0; i < text.length; i += 1) {
      view.setUint8(offset + i, text.charCodeAt(i));
    }
  };

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + dataLength, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * bytesPerSample, true);
  view.setUint16(32, bytesPerSample, true);
  view.setUint16(34, 16, true);
  writeString(36, 'data');
  view.setUint32(40, dataLength, true);

  let offset = 44;
  for (let i = 0; i < float32Array.length; i += 1) {
    const sample = Math.max(-1, Math.min(1, float32Array[i]));
    view.setInt16(offset, sample < 0 ? sample * 0x8000 : sample * 0x7fff, true);
    offset += 2;
  }

  return buffer;
}

async function speakText(text) {
  if (!state.isTTSEnabled || !text.trim()) {
    return;
  }

  const response = await fetch('/api/voice/tts', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text, voice: state.settings.voice }),
  });

  if (!response.ok) {
    return;
  }

  const audioBlob = await response.blob();
  const url = URL.createObjectURL(audioBlob);
  const audio = new Audio(url);
  audio.onended = () => URL.revokeObjectURL(url);
  audio.play().catch(() => URL.revokeObjectURL(url));
}

async function loadModels() {
  try {
    const response = await fetch('/api/llm/models');
    if (!response.ok) {
      return;
    }

    const payload = await response.json();
    const models = payload?.data || payload?.models || [];
    modelSelect.innerHTML = '';

    const normalized = models.map((item) => item.id || item.name || item).filter(Boolean);
    const fallback = normalized.length > 0 ? normalized : ['Qwen2.5-0.5B-Instruct-Q4_K_M.gguf'];

    fallback.forEach((modelName) => {
      const option = document.createElement('option');
      option.value = modelName;
      option.textContent = modelName;
      modelSelect.appendChild(option);
    });

    state.currentModel = modelSelect.value;
  } catch {
    modelSelect.innerHTML = '<option value="Qwen2.5-0.5B-Instruct-Q4_K_M.gguf">Qwen2.5-0.5B-Instruct-Q4_K_M.gguf</option>';
    state.currentModel = 'Qwen2.5-0.5B-Instruct-Q4_K_M.gguf';
  }
}

async function checkHealth() {
  try {
    const [llmResponse, voiceResponse] = await Promise.all([
      fetch('/api/llm/health'),
      fetch('/api/voice/health'),
    ]);

    const llmData = llmResponse.ok ? await llmResponse.json() : { ok: false };
    const voiceData = voiceResponse.ok ? await voiceResponse.json() : { stt: { ok: false }, tts: { ok: false } };

    setDot(llmDot, !!llmData.ok);
    setDot(sttDot, !!voiceData?.stt?.ok);
    setDot(ttsDot, !!voiceData?.tts?.ok);
  } catch {
    setDot(llmDot, false);
    setDot(sttDot, false);
    setDot(ttsDot, false);
  }
}

function setMicState(mode, statusText) {
  micBtn.classList.remove('idle', 'recording', 'processing');
  micBtn.classList.add(mode);
  micStatus.textContent = statusText;
  renderActionButtons();
}

function startWaveform() {
  const context = new AudioContext();
  const analyser = context.createAnalyser();
  analyser.fftSize = 128;
  const source = context.createMediaStreamSource(state.audioStream);
  source.connect(analyser);

  state.waveform.context = context;
  state.waveform.analyser = analyser;
  state.waveform.source = source;

  drawWaveform(analyser);
}

function stopWaveform() {
  if (state.waveform.frameId) {
    cancelAnimationFrame(state.waveform.frameId);
    state.waveform.frameId = null;
  }
  if (state.waveform.source) {
    state.waveform.source.disconnect();
    state.waveform.source = null;
  }
  if (state.waveform.context) {
    state.waveform.context.close();
    state.waveform.context = null;
  }

  const ctx = waveformCanvas.getContext('2d');
  ctx.clearRect(0, 0, waveformCanvas.width, waveformCanvas.height);
}

function drawWaveform(analyserNode) {
  const ctx = waveformCanvas.getContext('2d');
  const data = new Uint8Array(analyserNode.frequencyBinCount);

  const loop = () => {
    analyserNode.getByteFrequencyData(data);
    ctx.clearRect(0, 0, waveformCanvas.width, waveformCanvas.height);
    const barWidth = waveformCanvas.width / data.length;

    for (let i = 0; i < data.length; i += 1) {
      const value = data[i] / 255;
      const barHeight = Math.max(2, waveformCanvas.height * value);
      const x = i * barWidth;
      const y = waveformCanvas.height - barHeight;
      ctx.fillStyle = 'rgba(94, 140, 255, 0.85)';
      ctx.fillRect(x, y, barWidth - 1, barHeight);
    }

    if (state.isRecording) {
      state.waveform.frameId = requestAnimationFrame(loop);
    }
  };

  state.waveform.frameId = requestAnimationFrame(loop);
}

sendBtn.addEventListener('click', () => sendTextMessage(promptInput.value));
if (clearBtn) {
  clearBtn.addEventListener('click', () => {
    chatWindow.querySelectorAll('.message').forEach((message) => message.remove());
    syncChatEmptyState();
  });
}

if (settingsToggleBtn && settingsDialog) {
  settingsToggleBtn.addEventListener('click', () => {
    if (typeof settingsDialog.showModal === 'function' && !settingsDialog.open) {
      settingsDialog.showModal();
    }
  });
}

if (settingsCloseBtn && settingsDialog) {
  settingsCloseBtn.addEventListener('click', () => {
    settingsDialog.close();
  });
}

if (settingsDialog) {
  settingsDialog.addEventListener('click', (event) => {
    const rect = settingsDialog.getBoundingClientRect();
    const clickedInDialog = (
      rect.top <= event.clientY
      && event.clientY <= rect.top + rect.height
      && rect.left <= event.clientX
      && event.clientX <= rect.left + rect.width
    );
    if (!clickedInDialog) {
      settingsDialog.close();
    }
  });
}

promptInput.addEventListener('input', resizePromptInput);
promptInput.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    sendTextMessage(promptInput.value);
  }
});

micBtn.addEventListener('click', async () => {
  try {
    if (!state.isRecording) {
      await startRecording();
    } else {
      stopRecording();
    }
  } catch (error) {
    if (error.name === 'NotAllowedError') {
      setMicState('idle', 'Microphone access denied. Please allow mic access in browser settings and reload.');
    } else {
      setMicState('idle', `Mic error: ${error.message}`);
    }
  }
});

ttsToggle.addEventListener('change', () => {
  state.isTTSEnabled = ttsToggle.checked;
});

modelSelect.addEventListener('change', () => {
  state.currentModel = modelSelect.value;
});

voiceSelect.addEventListener('change', () => {
  state.settings.voice = voiceSelect.value;
});

temperatureInput.addEventListener('input', () => {
  state.settings.temperature = Number(temperatureInput.value);
  temperatureValue.textContent = temperatureInput.value;
});

maxTokensInput.addEventListener('change', () => {
  state.settings.max_tokens = Number(maxTokensInput.value);
});

systemPromptInput.addEventListener('change', () => {
  state.settings.systemPrompt = systemPromptInput.value;
});

async function init() {
  renderActionButtons();
  resizePromptInput();
  syncChatEmptyState();
  await loadModels();
  await checkHealth();
  setInterval(checkHealth, 15000);
}

init();
