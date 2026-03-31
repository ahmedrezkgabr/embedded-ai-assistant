SUMMARY = "llama.cpp LLM inference server"
HOMEPAGE = "https://github.com/ggerganov/llama.cpp"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=65fc6b420a6f24d1820d6f503f1c915f"

inherit cmake systemd

SRC_URI = " \
    git://github.com/ggerganov/llama.cpp.git;branch=master;protocol=https \
    file://llama-server.service \
"
SRCREV = "08f21453aec846867b39878500d725a05bd32683"

S = "${WORKDIR}/git"

EXTRA_OECMAKE = "-DLLAMA_BUILD_SERVER=ON -DLLAMA_NATIVE=OFF -DLLAMA_BUILD_TESTS=OFF"

RDEPENDS:${PN} += "libstdc++"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/bin/llama-server ${D}${bindir}/llama-server

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/llama-server.service ${D}${systemd_system_unitdir}/llama-server.service
}

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "llama-server.service"

FILES:${PN} += "${systemd_system_unitdir}/llama-server.service"
