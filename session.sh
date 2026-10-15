#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-44}"
BASE="fedora${VERSION}-server-base"
VM="agent-f${VERSION}-$(uuidgen | tr '[:upper:]' '[:lower:]')"
KEY="${VM_SSH_KEY:-$HOME/.ssh/agent_vm}"

STATE="$(mktemp -d)"
CLONED=0
RUN_PID=""

cleanup() {
  if [[ "$CLONED" == 1 ]]; then
    tart stop "$VM" >/dev/null 2>&1 || true
    if [[ -n "$RUN_PID" ]]; then
      wait "$RUN_PID" 2>/dev/null || true
    fi
    tart delete "$VM" >/dev/null 2>&1 || true
  fi
  rm -rf "$STATE"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

tart clone "$BASE" "$VM"
CLONED=1

tart run "$VM" --no-graphics --nested \
  >"$STATE/tart.log" 2>&1 &
RUN_PID=$!

SSH=(
  -i "$KEY"
  -o IdentitiesOnly=yes
  -o BatchMode=yes
  -o ConnectTimeout=3
  -o ConnectionAttempts=1
  -o StrictHostKeyChecking=accept-new
  -o "UserKnownHostsFile=$STATE/known_hosts"
)

READY=0
for ((attempt = 0; attempt < 120; attempt++)); do
  if ! kill -0 "$RUN_PID" 2>/dev/null; then
    cat "$STATE/tart.log" >&2
    exit 1
  fi

  IP="$(tart ip "$VM" 2>/dev/null || true)"

  if [[ -n "$IP" ]] &&
     ssh "${SSH[@]}" "agent@$IP" true 2>/dev/null; then
    READY=1
    break
  fi

  sleep 2
done

if [[ "$READY" != 1 ]]; then
  echo "Timed out waiting for SSH." >&2
  cat "$STATE/tart.log" >&2
  exit 1
fi

ssh "${SSH[@]}" "agent@$IP" 'bash -se' < provision.sh

echo "Disposable VM: $VM"
echo "Export or push your work before exiting."

# This new connection also picks up group membership changes.
ssh "${SSH[@]}" -t "agent@$IP"
