SUMMARY = "AI Assistant full offline image"
LICENSE = "MIT"

inherit core-image

IMAGE_FEATURES += "ssh-server-openssh debug-tweaks"

IMAGE_INSTALL:append = " \
  nodejs \
  llama-cpp \
  whisper-cpp \
  piper-tts \
  alsa-utils \
  alsa-lib \
  ai-assistant-backend \
  curl \
  bash \
  htop \
"

IMAGE_ROOTFS_EXTRA_SPACE = "4194304"
