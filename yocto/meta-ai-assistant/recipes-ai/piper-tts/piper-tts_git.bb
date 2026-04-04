SUMMARY = "Piper TTS local text-to-speech"
HOMEPAGE = "https://github.com/rhasspy/piper"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=b6d69b1c71f50f7f5d391fe7da6e6e4f"

inherit cmake

FILESEXTRAPATHS:prepend := "${TOPDIR}/../tts/models:"

SRC_URI = " \
    gitsm://github.com/rhasspy/piper.git;branch=master;protocol=https \
    file://en_US-lessac-low.onnx \
    file://en_US-lessac-low.onnx.json \
"
SRCREV = "73c04d81d5590ecc46e522de3601ce7fb29fc2be"

S = "${WORKDIR}/git"

DEPENDS += "onnxruntime espeak-ng fmt spdlog"
RDEPENDS:${PN} += "onnxruntime espeak-ng espeak-ng-data libstdc++"

EXTRA_OECMAKE = " \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_NATIVE=OFF \
    -DONNXRUNTIME_DIR=${RECIPE_SYSROOT}${prefix} \
"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 $(find ${B} -type f -name piper | head -n 1) ${D}${bindir}/piper
    if find ${B} -type f -name piper_phonemize | grep -q .; then
        install -m 0755 $(find ${B} -type f -name piper_phonemize | head -n 1) ${D}${bindir}/piper_phonemize
    fi

    install -d ${D}/opt/ai-assistant/models
    install -m 0644 ${WORKDIR}/en_US-lessac-low.onnx ${D}/opt/ai-assistant/models/en_US-lessac-low.onnx
    install -m 0644 ${WORKDIR}/en_US-lessac-low.onnx.json ${D}/opt/ai-assistant/models/en_US-lessac-low.onnx.json
}

FILES:${PN} += " /opt/ai-assistant/models "
