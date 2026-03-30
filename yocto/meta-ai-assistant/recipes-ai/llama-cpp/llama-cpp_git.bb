SUMMARY = "llama.cpp LLM inference server"
HOMEPAGE = "https://github.com/ggerganov/llama.cpp"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=65fc6b420a6f24d1820d6f503f1c915f"

inherit cmake systemd

SRC_URI = "git://github.com/ggerganov/llama.cpp.git;branch=master;protocol=https"
SRCREV = "ca2f5cc3f545a9ba6feeeaeefe0cb5c7d0d04c10"

S = "${WORKDIR}/git"

EXTRA_OECMAKE = "-DLLAMA_BUILD_SERVER=ON -DLLAMA_NATIVE=OFF -DLLAMA_BUILD_TESTS=OFF"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/bin/llama-server ${D}${bindir}/llama-server

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/llama-server.service ${D}${systemd_system_unitdir}/llama-server.service
}

SRC_URI += "file://llama-server.service"

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "llama-server.service"

FILES:${PN} += "${systemd_system_unitdir}/llama-server.service"
