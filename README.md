# Agent Jail

Sandboxing environment on Apple Silicon macOS using [Tart](https://tart.run) VMs (Fedora Linux aarch64) with nested virtualization (`/dev/kvm`) for isolated, persistent coding agent sessions.

## Architecture

```
Fedora Server aarch64 ISO + Kickstart + Packer
│
▼
Pre-baked Fedora Base (`fedora44-server-base`)
├── Toolchains: Go, Python 3, Rust (`rustup`), `uv`, `agy` CLI
├── Container Engine: Podman (`podman-docker`, `docker.socket`)
├── Groups: `docker`, `kvm`
└── Virtualization: Nested KVM (`/dev/kvm`) enabled
│
▼
Clone → Boot with `--nested` & VirtioFS → Persistent Session
├── `/home/agent/workspace`: Isolated VM-only storage
└── `/home/agent/shared`: Synced with host `$HOME/Documents/VMs/LinuxShared`
```

## Features

- **Pre-baked Developer Toolchain**: Go, Python 3, Rust (`rustup` / `cargo`), `uv`, and `agy` CLI are baked into the base image. New session clones launch in seconds.
- **Persistent Sessions**: VMs are never deleted automatically on session exit. Stop, reconnect, or delete them whenever you choose.
- **Dual Storage Model**:
    - `/home/agent/workspace`: VM-local filesystem. Ideal for scratch work, experiments, and untrusted agent execution.
    - `/home/agent/shared`: Bi-directional VirtioFS shared folder mounted directly from `$HOME/Documents/VMs/LinuxShared` on the host.
- **Container Ready**: Podman pre-installed with `podman-docker` CLI wrapper, `podman.socket` enabled, and user `agent` pre-assigned to the `docker` group.
- **Nested Virtualization**: Hardware-accelerated `/dev/kvm` available inside the guest for nested VM or container workloads.

## Prerequisites

1. **Apple Silicon Mac** (M Series).
2. **Tart CLI**:
    ```bash
    brew install openai/cli/tart
    ```
3. **Packer**:
    ```bash
    brew install hashicorp/tap/packer
    ```
4. **SSH Key Pair**:
    ```bash
    ssh-keygen -t ed25519 -f "$HOME/.ssh/agent_jail" -C "agent_jail" -N ""
    ```
5. **Host Shared Directory**:
    ```bash
    mkdir -p "$HOME/Documents/VMs/LinuxShared"
    ```
6. **Fedora Server aarch64 ISO**: Download from [fedoraproject.org](https://fedoraproject.org).

---

## 1. Build the Base Image

Initialize the Tart Packer plugin and build the reusable base image:

```bash
packer init base.pkr.hcl

packer build \
  -var 'fedora_version=44' \
  -var "iso_path=$PATH_TO_ISO" \
  -var "ssh_private_key_file=$HOME/.ssh/agent_jail" \
  -var "ssh_public_key_file=$HOME/.ssh/agent_jail.pub" \
  base.pkr.hcl
```

_Note: For future Fedora releases, pass `-var 'fedora_version=45'`._

---

## 2. Manage Sessions

`session.sh` provides commands to launch, list, reconnect, stop, and delete persistent agent VMs.

### Launch a New Session

```bash
# Launch a new Fedora 44 agent session (default shared folder: ~/Documents/VMs/LinuxShared)
./session.sh start 44

# Or using the shorthand:
./session.sh 44

# With a custom host shared directory:
./session.sh start 44 /path/to/custom/shared
```

### List Agent VMs

```bash
./session.sh list
```

### Reconnect / Resume a Session

Connect to an existing VM (automatically starts the VM if it is currently stopped):

```bash
./session.sh resume <vm-name>
```

### Stop a VM

```bash
./session.sh stop <vm-name>
```

### Delete a VM

```bash
./session.sh delete <vm-name>
```

---

## Environment & Path Reference

Inside the guest VM, the following environment is configured for user `agent`:

| Tool / Variable     | Path / Setting                       | Notes                                              |
| ------------------- | ------------------------------------ | -------------------------------------------------- |
| **Go**              | `/usr/bin/go`                        | `GOPATH="$HOME/go"`, `GOBIN="$GOPATH/bin"`         |
| **Python**          | `/usr/bin/python3`                   | `python3-pip`, `python3-virtualenv`                |
| **uv**              | `~/.local/bin/uv`                    | Fast Python package manager                        |
| **Rust / Cargo**    | `~/.cargo/bin/cargo`                 | Installed via `rustup`                             |
| **agy CLI**         | `~/.local/bin/agy`                   | Google Antigravity CLI                             |
| **Podman / Docker** | `/usr/bin/podman`, `/usr/bin/docker` | `docker.socket` compatibility enabled              |
| **Nested KVM**      | `/dev/kvm`                           | User `agent` belongs to `kvm` and `docker` groups  |
| **VM Workspace**    | `/home/agent/workspace`              | VM-isolated filesystem                             |
| **Host Shared**     | `/home/agent/shared`                 | Synced with host `$HOME/Documents/VMs/LinuxShared` |
