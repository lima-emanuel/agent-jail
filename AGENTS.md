# AGENTS.md

Ephemeral sandboxing environment on Apple Silicon macOS using Tart VMs (Fedora Linux aarch64) with nested virtualization (`/dev/kvm`) for isolated coding agent sessions.

## Architecture & Lifecycle

- **Base Image Build (`base.pkr.hcl`, `kickstart.ks.pkrtpl`, `base-update.sh`)**:
  - Packer provisions a persistent base VM image (`fedora${fedora_version}-server-base`) from a local Fedora Server aarch64 ISO using the `cirruslabs/tart` Packer plugin.
  - Automates installation via Kickstart (`/ks.cfg`), configures passwordless sudo for user `agent`, enables SSH public key auth, runs `base-update.sh`, and validates `/dev/kvm`.
- **Ephemeral Session (`session.sh`, `provision.sh`)**:
  - Clones `fedora${VERSION}-server-base` to a uniquely named VM (`agent-f${VERSION}-<uuid>`).
  - Launches headless VM with `tart run --nested`, awaits SSH availability via `tart ip`.
  - Streams `provision.sh` to install base development tools (`gcc`, `make`, `python3`, `qemu-kvm`) and assert nested KVM availability.
  - Drops host into an interactive SSH shell.
  - **Trap cleanup on exit**: VM is automatically stopped and deleted on session termination (`EXIT`, `INT`, `TERM`). Any unpushed or unexported files are lost.

## Essential Commands

- **Initialize Packer plugin**:
  ```bash
  packer init base.pkr.hcl
  ```

- **Build Base Image**:
  ```bash
  packer build \
    -var 'fedora_version=44' \
    -var "iso_path=$HOME/Downloads/YOUR-FEDORA-44-SERVER-AARCH64.iso" \
    -var "ssh_private_key_file=$HOME/.ssh/agent_vm" \
    -var "ssh_public_key_file=$HOME/.ssh/agent_vm.pub" \
    base.pkr.hcl
  ```

- **Launch Ephemeral Session**:
  ```bash
  ./session.sh 44
  # With explicit SSH key override:
  VM_SSH_KEY="$HOME/.ssh/agent_vm" ./session.sh 44
  ```

## Operational Gotchas & Conventions

- **SSH Key Default**: `session.sh` defaults to `$HOME/.ssh/agent_vm` (customizable via `VM_SSH_KEY`). Ensure this matches the key provided during `packer build`.
- **Data Persistence**: Clones are strictly ephemeral. Changes inside `~/workspace` inside the VM must be pushed to a remote git branch or transferred out before exiting the SSH shell.
- **Nested Virtualization**: Requires Apple Silicon macOS host support for Tart nested virtualization (`--nested`). The guest depends on `/dev/kvm` existing and user `agent` belonging to the `kvm` group.
- **Packer Template Nuances**:
  - `kickstart.ks.pkrtpl` uses `${fedora_version}` in the metalink repo URL. Ensure `fedora_version = var.fedora_version` is passed in `templatefile()` inside `base.pkr.hcl`.
  - `base.pkr.hcl` `boot_command` hardcodes `inst.stage2=hd:LABEL=Fedora-S-dvd-aarch64-44`. Verify the ISO volume label when upgrading to future Fedora releases (e.g., Fedora 45).
