SUMMARY = "AI Assistant Express.js backend"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

FILESEXTRAPATHS:prepend := "${THISDIR}/../ai-assistant-backend/files:${TOPDIR}/../backend:${TOPDIR}/../backend/deploy:"

SRC_URI = " \
	file://ai-assistant.service \
"

S = "${WORKDIR}"

do_install() {
		install -d ${D}/opt/ai-assistant/backend
		install -d ${D}/opt/ai-assistant/models

		if [ ! -d ${TOPDIR}/../backend ]; then
				bbfatal "Missing backend source directory at ${TOPDIR}/../backend"
		fi

		if [ ! -f ${TOPDIR}/../backend/package-lock.json ]; then
				bbfatal "backend/package-lock.json missing; run npm ci in backend before Yocto build"
		fi

		if [ ! -d ${TOPDIR}/../backend/node_modules ]; then
				bbfatal "backend/node_modules missing; run npm ci --omit=dev in backend before Yocto build"
		fi

		cp -a ${TOPDIR}/../backend/. ${D}/opt/ai-assistant/backend/
		rm -f ${D}/opt/ai-assistant/backend/.env

		[ -f ${TOPDIR}/../llm/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf ] || bbfatal "Missing required LLM model: llm/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
		[ -f ${TOPDIR}/../stt/models/ggml-tiny.en.bin ] || bbfatal "Missing required STT model: stt/models/ggml-tiny.en.bin"

		cp -a ${TOPDIR}/../llm/models/*.gguf ${D}/opt/ai-assistant/models/ 2>/dev/null || true
		cp -a ${TOPDIR}/../stt/models/*.bin ${D}/opt/ai-assistant/models/ 2>/dev/null || true

		cat > ${D}/opt/ai-assistant/.env <<EOF
PORT=3000
TMP_DIR=/tmp
UPLOAD_DIR=/tmp/ai-assistant/uploads
LOG_FILE=/tmp/ai-assistant/backend.log
LLM_BASE_URL=http://localhost:11434
LLM_DEFAULT_MODEL=Qwen2.5-0.5B-Instruct-Q4_K_M.gguf
LLM_TIMEOUT=60000
LLM_MAX_TOKENS=128
LLM_TEMPERATURE=0
LLM_TOP_P=0.2
LLM_FREQUENCY_PENALTY=0
LLM_PRESENCE_PENALTY=0
LLM_STRICT_SYSTEM_PROMPT=You are an embedded Linux voice assistant running offline. Always reply in English only using ASCII characters. Keep answers concise and factual.
WHISPER_BIN=/usr/bin/whisper-cli
WHISPER_MODEL=/opt/ai-assistant/models/ggml-tiny.en.bin
WHISPER_TIMEOUT=30000
PIPER_BIN=/usr/bin/piper
PIPER_VOICE=/opt/ai-assistant/models/en_US-lessac-low.onnx
PIPER_VOICE_DIR=/opt/ai-assistant/models
PIPER_PHONEMIZE_BIN=/usr/bin/piper_phonemize
PIPER_TIMEOUT=20000
NODE_ENV=production
EOF

		install -d ${D}${systemd_system_unitdir}
		install -m 0644 ${WORKDIR}/ai-assistant.service ${D}${systemd_system_unitdir}/ai-assistant.service
}

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "ai-assistant.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

FILES:${PN} += " \
	/opt/ai-assistant/backend \
	/opt/ai-assistant/models \
	/opt/ai-assistant/.env \
	${systemd_system_unitdir}/ai-assistant.service \
"

RDEPENDS:${PN} += " \
	nodejs \
	llama-cpp \
	whisper-cpp \
	piper-tts \
	bash \
	curl \
"
