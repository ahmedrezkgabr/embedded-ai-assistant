SUMMARY = "Piper TTS local text-to-speech"
HOMEPAGE = "https://github.com/rhasspy/piper"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=b6d69b1c71f50f7f5d391fe7da6e6e4f"

inherit cmake

SRC_URI = "git://github.com/rhasspy/piper.git;branch=master;protocol=https"
SRCREV = "${AUTOREV}"

S = "${WORKDIR}/git"

DEPENDS += "onnxruntime espeak-ng"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/piper ${D}${bindir}/piper
}
