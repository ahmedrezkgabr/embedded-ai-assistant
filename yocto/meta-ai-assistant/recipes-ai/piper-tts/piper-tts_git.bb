SUMMARY = "Piper TTS local text-to-speech"
HOMEPAGE = "https://github.com/rhasspy/piper"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=b6d69b1c71f50f7f5d391fe7da6e6e4f"

inherit cmake

SRC_URI = "git://github.com/rhasspy/piper.git;branch=master;protocol=https"
SRCREV = "73c04d81d5590ecc46e522de3601ce7fb29fc2be"

S = "${WORKDIR}/git"

DEPENDS += "onnxruntime espeak-ng"
RDEPENDS:${PN} += "onnxruntime espeak-ng espeak-ng-data libstdc++"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/piper ${D}${bindir}/piper
    if [ -f ${B}/piper_phonemize ]; then
        install -m 0755 ${B}/piper_phonemize ${D}${bindir}/piper_phonemize
    fi
}
