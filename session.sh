#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

KEY="${VM_SSH_KEY:-$HOME/.ssh/agent_jail}"
DEFAULT_SHARED="$HOME/Documents/VMs/LinuxShared"

subcommand="${1:-start}"
case "$subcommand" in
  list)
    echo "Active and stopped agent-jail VMs:"
    tart list | grep -E '^agent-f' || echo "No agent-jail VMs found."
    exit 0
    ;;
  stop)
    VM="${2:?Usage: ./session.sh stop <vm-name>}"
    tart stop "$VM"
    exit 0
    ;;
  delete)
    VM="${2:?Usage: ./session.sh delete <vm-name>}"
    tart stop "$VM" >/dev/null 2>&1 || true
    tart delete "$VM"
    echo "Deleted $VM"
    exit 0
    ;;
  resume|attach)
    VM="${2:?Usage: ./session.sh resume <vm-name>}"
    HOST_SHARED="${3:-${HOST_SHARED:-$DEFAULT_SHARED}}"
    mkdir -p "$HOST_SHARED"

    if [[ ! -f "$KEY" ]]; then
      echo "Error: SSH private key not found at $KEY" >&2
      exit 1
    fi

    IP="$(tart ip "$VM" 2>/dev/null || true)"
    if [[ -z "$IP" ]]; then
      echo "VM '$VM' is stopped. Starting in background..."
      tart run "$VM" --no-graphics --nested \
        --dir="shared:$HOST_SHARED:tag=shared" >/dev/null 2>&1 &
      for ((attempt = 0; attempt < 30; attempt++)); do
        IP="$(tart ip "$VM" 2>/dev/null || true)"
        [[ -n "$IP" ]] && break
        sleep 2
      done
    fi

    if [[ -z "$IP" ]]; then
      echo "Failed to get IP address for VM '$VM'." >&2
      exit 1
    fi

    echo "Connecting to $VM at $IP..."
    exec ssh -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -t "agent@$IP"
    ;;
  build)
    shift 1 || true
    exec ./build-base.sh "${@}"
    ;;
  start)
    shift 1 || true
    VERSION="${1:-44}"
    HOST_SHARED="${2:-${HOST_SHARED:-$DEFAULT_SHARED}}"
    ;;
  [0-9]*)
    VERSION="$subcommand"
    HOST_SHARED="${2:-${HOST_SHARED:-$DEFAULT_SHARED}}"
    ;;
  *)
    echo "Unknown command: $subcommand" >&2
    echo "Usage: $0 [start [VERSION] [HOST_SHARED_DIR]] | build [VERSION] <ISO_PATH> | list | resume <vm> | stop <vm> | delete <vm>" >&2
    exit 1
    ;;
esac

if [[ ! -f "$KEY" ]]; then
  echo "Error: SSH private key not found at $KEY" >&2
  echo "Generate one with: ssh-keygen -t ed25519 -f $KEY -N ''" >&2
  exit 1
fi

BASE="fedora${VERSION}-server-base"
VM="agent-f${VERSION}-$(uuidgen | tr '[:upper:]' '[:lower:]')"
mkdir -p "$HOST_SHARED"

STATE="$(mktemp -d)"
RUN_PID=""

trap 'rm -rf "$STATE"' EXIT

echo "Cloning $BASE to $VM..."
tart clone "$BASE" "$VM"

echo "Booting $VM with nested virtualization and shared folder: $HOST_SHARED..."
tart run "$VM" --no-graphics --nested \
  --dir="shared:$HOST_SHARED:tag=shared" \
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
echo "Waiting for SSH to become available..."
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

echo "Running guest session initialization..."
ssh "${SSH[@]}" "agent@$IP" 'bash -se' < provision.sh

echo ""
echo "=== VM Ready: $VM ==="
echo "IP address:         $IP"
echo "VM-only workspace:  /home/agent/workspace"
echo "Host shared folder: $HOST_SHARED -> /home/agent/shared"
echo "To reconnect:       ./session.sh resume $VM"
echo "To stop:            ./session.sh stop $VM"
echo "To delete:          ./session.sh delete $VM"
echo "======================"
echo ""

# Interactive shell
ssh -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$STATE/known_hosts" -t "agent@$IP"

echo ""
echo "Session closed. VM '$VM' remains running in the background."
echo "To reconnect: ./session.sh resume $VM"
echo "To stop:      ./session.sh stop $VM"
echo "To delete:    ./session.sh delete $VM"
