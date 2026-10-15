#!/usr/bin/env bash
set -euo pipefail

sudo dnf install -y \
  git \
  gcc \
  gcc-c++ \
  make \
  python3 \
  python3-pip \
  qemu-kvm

# Fail instead of silently running without nested virtualization.
test -c /dev/kvm || {
  echo "Nested virtualization unavailable: /dev/kvm is missing." >&2
  exit 1
}

if getent group kvm >/dev/null; then
  sudo usermod -aG kvm "$USER"
fi

mkdir -p "$HOME/workspace"

# Install your chosen coding agent here.
# Prefer explicit runtime and agent versions.
