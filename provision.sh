#!/usr/bin/env bash
set -euo pipefail

# Fail instead of silently running without nested virtualization.
test -c /dev/kvm || {
  echo "Nested virtualization unavailable: /dev/kvm is missing." >&2
  exit 1
}

# Ensure required user groups are created and assigned
if ! getent group docker >/dev/null; then
  sudo groupadd docker
fi
if getent group kvm >/dev/null; then
  sudo usermod -aG docker,kvm "$USER"
else
  sudo usermod -aG docker "$USER"
fi

# Dual storage: VM-only isolated workspace and host-shared folder
mkdir -p "$HOME/workspace"
mkdir -p "$HOME/shared"
mkdir -p "$HOME/go/bin" "$HOME/.local/bin"

# Mount VirtioFS host shared directory if available and not already mounted
if ! mountpoint -q "$HOME/shared"; then
  sudo mount -t virtiofs shared "$HOME/shared" 2>/dev/null || true
fi

# Ensure environment variables are configured in .bashrc
if ! grep -q "GOPATH" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" << 'EOF'

# Development environment paths
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"
export PATH="$GOBIN:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
EOF
fi
