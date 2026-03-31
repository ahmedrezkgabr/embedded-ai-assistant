SUMMARY = "whisper.cpp offline speech recognition"
HOMEPAGE = "https://github.com/ggerganov/whisper.cpp"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=65fc6b420a6f24d1820d6f503f1c915f"

inherit cmake

SRC_URI = "git://github.com/ggerganov/whisper.cpp.git;branch=master;protocol=https"
SRCREV = "95ea8f9bfb03a15db08a8989966fd1ae3361e20d"

S = "${WORKDIR}/git"

RDEPENDS:${PN} += "libstdc++"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/bin/whisper-cli ${D}${bindir}/whisper-cli
}
