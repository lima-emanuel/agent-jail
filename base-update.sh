#!/usr/bin/env bash
set -euo pipefail

sudo dnf -y --refresh upgrade

# Developer packages, compiler toolchains, system libraries, and container runtimes
sudo dnf install -y \
  git curl wget ca-certificates \
  make cmake ninja-build \
  gcc gcc-c++ \
  pkgconf-pkg-config \
  openssl-devel zlib-devel bzip2-devel \
  libffi-devel readline-devel sqlite-devel \
  tar unzip zip \
  jq ripgrep fd-find \
  golang python3 python3-pip python3-virtualenv \
  qemu-kvm podman podman-docker

# User and group management
if ! getent group docker >/dev/null; then
  sudo groupadd docker
fi
sudo usermod -aG docker agent
if getent group kvm >/dev/null; then
  sudo usermod -aG kvm agent
fi

# Enable Podman socket for Docker API compatibility
sudo systemctl enable podman.socket
sudo ln -sf /run/podman/podman.sock /var/run/docker.sock || true

# User workspaces and binary directories
sudo -u agent mkdir -p \
  /home/agent/workspace \
  /home/agent/shared \
  /home/agent/go/bin \
  /home/agent/.local/bin

# Install uv (Python package manager)
sudo -u agent bash -c '
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
'

# Install Rust toolchain via rustup
sudo -u agent bash -c '
  if ! command -v rustup >/dev/null 2>&1; then
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  fi
'

# Install agy CLI
sudo -u agent bash -c '
  if ! command -v agy >/dev/null 2>&1; then
    curl -fsSL https://antigravity.google/cli/install.sh | bash
  fi
'

# Configure environment variables in .bashrc
sudo -u agent bash -c '
  if ! grep -q "GOPATH" /home/agent/.bashrc 2>/dev/null; then
    cat >> /home/agent/.bashrc << '\''EOF'\''

# Development environment paths
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"
export PATH="$GOBIN:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
EOF
  fi
'

# Mount host shared folder via VirtioFS on boot if available
if ! grep -q "shared /home/agent/shared virtiofs" /etc/fstab 2>/dev/null; then
  echo "shared /home/agent/shared virtiofs rw,nofail,_netdev 0 0" | sudo tee -a /etc/fstab >/dev/null
fi

date -u +"%Y-%m-%dT%H:%M:%SZ" |
  sudo tee /etc/agent-base-built-at >/dev/null
