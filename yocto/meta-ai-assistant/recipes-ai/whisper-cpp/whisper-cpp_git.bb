SUMMARY = "whisper.cpp offline speech recognition"
HOMEPAGE = "https://github.com/ggerganov/whisper.cpp"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=65fc6b420a6f24d1820d6f503f1c915f"

inherit cmake

SRC_URI = "git://github.com/ggerganov/whisper.cpp.git;branch=master;protocol=https"
SRCREV = "1b6cd50d1e370a2fbd7eb4c6e1e62ba94a37bfa2"

S = "${WORKDIR}/git"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/bin/whisper-cli ${D}${bindir}/whisper-cli
}
