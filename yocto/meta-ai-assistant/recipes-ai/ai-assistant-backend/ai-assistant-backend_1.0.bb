SUMMARY = "AI Assistant Express.js backend"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = " \
  file://ai-assistant.service \
  file://llama-server.service \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}/opt/ai-assistant/backend
    install -d ${D}/opt/ai-assistant/models

  if [ -d ${TOPDIR}/../backend ]; then
    cp -a ${TOPDIR}/../backend/. ${D}/opt/ai-assistant/backend/
    rm -rf ${D}/opt/ai-assistant/backend/node_modules
    rm -f ${D}/opt/ai-assistant/backend/.env
  fi

  if [ -d ${TOPDIR}/../llm/models ]; then
    cp -a ${TOPDIR}/../llm/models/*.gguf ${D}/opt/ai-assistant/models/ 2>/dev/null || true
  fi
  if [ -d ${TOPDIR}/../stt/models ]; then
    cp -a ${TOPDIR}/../stt/models/*.bin ${D}/opt/ai-assistant/models/ 2>/dev/null || true
  fi
  if [ -d ${TOPDIR}/../tts/models ]; then
    cp -a ${TOPDIR}/../tts/models/*.onnx* ${D}/opt/ai-assistant/models/ 2>/dev/null || true
  fi

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/ai-assistant.service ${D}${systemd_system_unitdir}/ai-assistant.service
    install -m 0644 ${WORKDIR}/llama-server.service ${D}${systemd_system_unitdir}/llama-server.service
}

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "ai-assistant.service llama-server.service"

FILES:${PN} += " \
  /opt/ai-assistant/backend \
  /opt/ai-assistant/models \
  ${systemd_system_unitdir}/ai-assistant.service \
  ${systemd_system_unitdir}/llama-server.service \
"
