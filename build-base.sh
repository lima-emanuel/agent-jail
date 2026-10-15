#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Allow flexible argument order:
# ./build-base.sh [VERSION] <ISO_PATH>
# ./build-base.sh <ISO_PATH> [VERSION]
if [[ $# -ge 1 && ("$1" == *.iso || -f "$1") ]]; then
  ISO_PATH="$1"
  FEDORA_VERSION="${2:-44}"
else
  FEDORA_VERSION="${1:-44}"
  ISO_PATH="${2:-${PATH_TO_ISO:-}}"
fi

KEY="${VM_SSH_KEY:-$HOME/.ssh/agent_jail}"
PUB_KEY="${KEY}.pub"

if [[ -z "$ISO_PATH" ]]; then
  echo "Usage: $0 [fedora_version] <path-to-fedora-iso>" >&2
  echo "   or: $0 <path-to-fedora-iso> [fedora_version]" >&2
  echo "Example: $0 44 ~/Downloads/Fedora-Server-netinst-aarch64-44.iso" >&2
  exit 1
fi

if [[ ! -f "$ISO_PATH" ]]; then
  echo "Error: Fedora ISO not found at '$ISO_PATH'" >&2
  exit 1
fi

if [[ ! -f "$KEY" || ! -f "$PUB_KEY" ]]; then
  echo "Generating SSH key pair at $KEY..."
  mkdir -p "$(dirname "$KEY")"
  ssh-keygen -t ed25519 -f "$KEY" -C "agent_jail" -N ""
fi

TMP_DIR="$(mktemp -d)"
OEMDRV_ISO="$TMP_DIR/oemdrv.iso"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Rendering Kickstart for Fedora $FEDORA_VERSION..."
SSH_PUB_CONTENT="$(cat "$PUB_KEY" | tr -d '\r\n')"

sed -e "s|\${fedora_version}|${FEDORA_VERSION}|g" \
    -e "s|\${ssh_public_key}|${SSH_PUB_CONTENT}|g" \
    kickstart.ks.pkrtpl > "$TMP_DIR/ks.cfg"

echo "Creating OEMDRV Kickstart ISO..."
hdiutil makehybrid -iso -joliet -default-volume-name OEMDRV -o "$OEMDRV_ISO" "$TMP_DIR" >/dev/null

echo "Starting Packer build with OEMDRV automated installation..."
exec packer build \
  -var "fedora_version=${FEDORA_VERSION}" \
  -var "iso_path=${ISO_PATH}" \
  -var "ssh_private_key_file=${KEY}" \
  -var "ssh_public_key_file=${PUB_KEY}" \
  -var "kickstart_iso_path=${OEMDRV_ISO}" \
  base.pkr.hcl
