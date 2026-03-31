#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$ROOT_DIR/poky" ]; then
  git clone --depth 1 -b scarthgap git://git.yoctoproject.org/poky "$ROOT_DIR/poky"
else
  echo "poky already present"
fi

if [ ! -d "$ROOT_DIR/meta-openembedded" ]; then
  git clone --depth 1 -b scarthgap https://github.com/openembedded/meta-openembedded.git "$ROOT_DIR/meta-openembedded"
else
  echo "meta-openembedded already present"
fi

if [ ! -d "$ROOT_DIR/meta-raspberrypi" ]; then
  git clone --depth 1 -b scarthgap https://github.com/agherzan/meta-raspberrypi.git "$ROOT_DIR/meta-raspberrypi"
else
  echo "meta-raspberrypi already present"
fi

echo
echo "Setup complete. Next steps:"
echo "1) source poky/oe-init-build-env build"
echo "2) cp $ROOT_DIR/conf/local.conf.sample conf/local.conf"
echo "3) cp $ROOT_DIR/conf/bblayers.conf.sample conf/bblayers.conf"
echo "4) bitbake ai-assistant-image"
