# AGENTS.md

Persistent sandboxing environment on Apple Silicon macOS using Tart VMs (Fedora Linux aarch64) with nested virtualization (`/dev/kvm`) for isolated coding agent sessions.

## Architecture & Lifecycle

- **Base Image Build (`build-base.sh`, `base.pkr.hcl`, `kickstart.ks.pkrtpl`, `base-update.sh`)**:
  - `build-base.sh` renders `kickstart.ks.pkrtpl` with the user's SSH public key into a lightweight `OEMDRV` ISO that Anaconda auto-discovers on boot.
  - Packer provisions a persistent base VM image (`fedora${fedora_version}-server-base`) from a local Fedora Server aarch64 ISO using the `cirruslabs/tart` plugin.
  - Automated installation runs in text mode without interactive Anaconda GUI, with progress visible in the Tart VM window.
  - `base-update.sh` pre-bakes full developer toolchains: Go, Python 3, Rust (`rustup` / `cargo`), `uv`, `agy` CLI, and Podman (`podman-docker`).
  - Pre-configures user groups (`docker`, `kvm`), enables `podman.socket`, and writes VirtioFS mount to `/etc/fstab`.
- **Persistent Session (`session.sh`, `provision.sh`)**:
  - Clones `fedora${VERSION}-server-base` to a uniquely named VM (`agent-f${VERSION}-<uuid>`).
  - Launches headless VM with `tart run --nested --dir="shared:$HOST_SHARED:tag=shared"`.
  - Streams `provision.sh` to ensure `/dev/kvm` presence, verify group permissions, and mount `/home/agent/shared`.
  - Drops host into an interactive SSH shell.
  - **No auto-deletion**: VMs persist when the SSH session disconnects. Stopping and deleting are manual only.

## Storage Architecture

- **VM-Only Workspace (`/home/agent/workspace`)**: Isolated filesystem inside the virtual disk. Ideal for scratchpad files, temporary builds, or untrusted execution.
- **Host Shared Folder (`/home/agent/shared`)**: Bi-directional VirtioFS mount synced directly with `$HOME/Documents/VMs/LinuxShared` on macOS (customizable via `./session.sh start <VERSION> <PATH>`).

## Essential Commands

- **Initialize Packer plugin**:
  ```bash
  packer init base.pkr.hcl
  ```

- **Build Base Image**:
  ```bash
  # Automated unattended install (opens Tart VM window to observe text-mode progress):
  ./build-base.sh 44 "$HOME/Downloads/YOUR-FEDORA-44-SERVER-AARCH64.iso"

  # Or via session.sh:
  ./session.sh build 44 "$HOME/Downloads/YOUR-FEDORA-44-SERVER-AARCH64.iso"
  ```

- **Manage Sessions (`session.sh`)**:
  ```bash
  # Launch new persistent session (default shared: ~/Documents/VMs/LinuxShared):
  ./session.sh start 44

  # List active and stopped agent VMs:
  ./session.sh list

  # Reconnect to an existing VM:
  ./session.sh resume <vm-name>

  # Stop a running VM:
  ./session.sh stop <vm-name>

  # Delete a VM:
  ./session.sh delete <vm-name>
  ```

## Operational Gotchas & Conventions

- **SSH Key Default**: All scripts default to `$HOME/.ssh/agent_jail` (overridable via `VM_SSH_KEY`). Ensure this matches the key provided during `packer build`.
- **Manual Teardown**: VMs are never deleted automatically on session exit. To prevent disk space accumulation in `~/.tart/vms`, use `./session.sh list` and `./session.sh delete <vm-name>` when finished.
- **Container Runtime**: Uses Podman with `podman-docker` CLI wrapper. `podman.socket` is enabled and symlinked to `/var/run/docker.sock` for Docker API compatibility. User `agent` belongs to the `docker` group.
- **Nested Virtualization**: Requires Apple Silicon macOS host support for Tart nested virtualization (`--nested`). Guest exposes `/dev/kvm` for nested VM and hypervisor workloads.
- **Host Shared Path**: The default shared directory on the host is `$HOME/Documents/VMs/LinuxShared`. Ensure this directory exists on macOS before starting a session.
