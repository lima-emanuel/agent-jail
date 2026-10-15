# Dev Environment, Persistent Sessions, VirtioFS Sharing, and Tooling Implementation Plan

## Change summary
Transform `agent-jail` from an auto-destroying sandbox into a persistent VM environment equipped with Go, Python, and Rust toolchains, `uv`, `rustup`, `agy` CLI, and `podman` (with Docker emulation). Pre-bake all heavy toolchains into the base image for instantaneous session launches, standardize on `$HOME/.ssh/agent_jail` as the default SSH key, support dual storage (`/home/agent/workspace` VM-only and `/home/agent/shared` VirtioFS host mount backed by `$HOME/Documents/VMs/LinuxShared`), introduce session management subcommands to `session.sh` (`start`, `list`, `resume`, `stop`, `delete`), fix Packer template bugs, and update documentation across `README.md` and `AGENTS.md`.

### Current-state findings
Precise repository evidence:
- `session.sh:9`: Default SSH key is hardcoded to `KEY="${VM_SSH_KEY:-$HOME/.ssh/agent_vm}"`, contradicting `README.md:29-30`.
- `session.sh:15-28`: `cleanup()` traps `EXIT`, `INT`, and `TERM` to automatically run `tart stop "$VM"` and `tart delete "$VM"`, preventing work persistence.
- `session.sh:33-35`: Runs Tart without directory sharing flags (`--dir`).
- `session.sh:73-77`: Hardcoded workflow assumes single disposable session per invocation without subcommands to list, resume, stop, or delete VMs.
- `provision.sh:4-11`: Installs minimal build tools on every session boot over the network, missing Golang, Rust, uv, agy CLI, and container runtimes.
- `provision.sh:19-21`: Adds user `agent` to group `kvm`, but group `docker` is neither created nor assigned.
- `provision.sh:23`: Creates only `$HOME/workspace`; no host-shared directory mount point exists.
- `base-update.sh:4`: Only runs `sudo dnf -y --refresh upgrade`; does not bake developer toolchains into the base image.
- `base.pkr.hcl:43-50`: Invokes `templatefile("${path.root}/kickstart.ks.pkrtpl", { ssh_public_key = ... })` without passing `fedora_version`, causing `packer build` to fail when evaluating `kickstart.ks.pkrtpl:2`.
- `base.pkr.hcl:60`: Hardcodes `inst.stage2=hd:LABEL=Fedora-S-dvd-aarch64-44`, breaking builds for future Fedora releases.
- `README.md:1-18`: Depicts disposable VM workflow with auto-teardown.
- `AGENTS.md:15, 29, 38, 43`: References `$HOME/.ssh/agent_vm` and auto-destroy trap behavior.

---

## Proposed design

### Responsibilities and Boundaries
1. **`base-update.sh` (Base Image Provisioning)**:
   - Upgrades base system packages via DNF.
   - Installs core developer dependencies, compilers, libraries, tools, and runtimes:
     `git`, `curl`, `wget`, `ca-certificates`, `make`, `cmake`, `ninja-build`, `gcc`, `gcc-c++`, `pkgconf-pkg-config`, `openssl-devel`, `zlib-devel`, `bzip2-devel`, `libffi-devel`, `readline-devel`, `sqlite-devel`, `tar`, `unzip`, `zip`, `jq`, `ripgrep`, `fd-find`, `golang`, `python3`, `python3-pip`, `python3-virtualenv`, `qemu-kvm`, `podman`, `podman-docker`.
   - Creates `docker` group if missing and adds `agent` to `docker` and `kvm`.
   - Enables `podman.socket` (`sudo systemctl enable --now podman.socket`) and creates Docker socket symlink `/var/run/docker.sock` for Docker client compatibility.
   - Installs `uv` via `curl -LsSf https://astral.sh/uv/install.sh | sh` into `/home/agent/.local/bin`.
   - Installs `rustup` via `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y` into `/home/agent/.cargo/bin`.
   - Installs `agy` CLI via `curl -fsSL https://antigravity.google/cli/install.sh | bash` into `/home/agent/.local/bin`.
   - Configures `/home/agent/.bashrc` with:
     ```bash
     export GOPATH="$HOME/go"
     export GOBIN="$GOPATH/bin"
     export PATH="$GOBIN:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
     ```
   - Adds `/etc/fstab` entry for VirtioFS mount:
     `shared /home/agent/shared virtiofs rw,nofail,_netdev 0 0`
   - Configures `/home/agent/workspace` (VM-only storage) and `/home/agent/shared` (mount point).

2. **`base.pkr.hcl` & `kickstart.ks.pkrtpl`**:
   - Fixes `base.pkr.hcl` by passing `fedora_version = var.fedora_version` to `templatefile`.
   - Parameterizes `inst.stage2=hd:LABEL=Fedora-S-dvd-aarch64-${var.fedora_version}` in `boot_command`.

3. **`session.sh` (Session Launcher and VM Manager)**:
   - Standardizes default SSH key to `$HOME/.ssh/agent_jail` (overridable via `VM_SSH_KEY`).
   - Supports CLI subcommands:
     - `./session.sh` or `./session.sh start [VERSION] [HOST_SHARED_DIR]`: Clones base image, launches Tart VM with `--nested` and `--dir="shared:$HOST_SHARED:tag=shared"`, where `$HOST_SHARED` defaults to `$HOME/Documents/VMs/LinuxShared`.
     - `./session.sh list`: Lists running and stopped `agent-f*` VMs via `tart list`.
     - `./session.sh resume <VM_NAME>`: Connects to an existing VM via SSH (booting it if stopped).
     - `./session.sh stop <VM_NAME>`: Stops a running VM via `tart stop`.
     - `./session.sh delete <VM_NAME>`: Stops and deletes a VM via `tart delete`.
   - Removes automatic stop/delete cleanup traps; VM remains running when SSH disconnects.
   - Cleans up temporary `$STATE` directory on exit.

4. **`provision.sh` (In-Guest Session Init)**:
   - Lightweight and idempotent check run on session boot.
   - Ensures `/home/agent/workspace` and `/home/agent/shared` exist.
   - Verifies VirtioFS mount at `/home/agent/shared`; mounts if not already mounted.
   - Validates `/dev/kvm` presence.
   - Ensures user group memberships (`kvm`, `docker`) are active.

5. **`README.md` & `AGENTS.md`**:
   - Updated with full documentation of the persistent architecture, `$HOME/Documents/VMs/LinuxShared` folder sharing, podman runtime, base image build steps, session subcommands, and SSH key configuration.

---

## Implementation plan

1. `base.pkr.hcl` — `Template Variables and Boot Parameterization`
   - Change:
     1. Pass `fedora_version = var.fedora_version` into `templatefile` at line 43.
     2. Update line 60 boot command to use `"inst.stage2=hd:LABEL=Fedora-S-dvd-aarch64-${var.fedora_version} "`.
   - Rationale: Resolves template evaluation failure and enables building future Fedora versions.
   - Dependencies: None.

2. `base-update.sh` — `Base Image Pre-Baking`
   - Change:
     1. Install full package suite via DNF: `git curl wget ca-certificates make cmake ninja-build gcc gcc-c++ pkgconf-pkg-config openssl-devel zlib-devel bzip2-devel libffi-devel readline-devel sqlite-devel tar unzip zip jq ripgrep fd-find golang python3 python3-pip python3-virtualenv qemu-kvm podman podman-docker`.
     2. Ensure group `docker` exists; add `agent` to `docker` and `kvm`.
     3. Enable `podman.socket` via `systemctl enable podman.socket` and symlink `/var/run/docker.sock` to `/run/podman/podman.sock` if needed.
     4. Install `uv`, `rustup`, and `agy` CLI for user `agent`.
     5. Create `/home/agent/go/bin`, `/home/agent/.local/bin`, `/home/agent/workspace`, and `/home/agent/shared`.
     6. Configure `/home/agent/.bashrc` with `GOPATH`, `GOBIN`, and updated `PATH`.
     7. Append VirtioFS mount entry to `/etc/fstab`.
   - Rationale: Eliminates 3–5 minute wait time during session launch by pre-baking all toolchains.
   - Dependencies: Step 1.

3. `session.sh` — `Subcommands, Persistence, and VirtioFS Mount`
   - Change:
     1. Set `KEY="${VM_SSH_KEY:-$HOME/.ssh/agent_jail}"`.
     2. Implement subcommand parser: `start`, `list`, `resume`, `stop`, `delete`.
     3. For `start`:
        - Set `HOST_SHARED="${3:-${HOST_SHARED:-$HOME/Documents/VMs/LinuxShared}}"`.
        - Create `$HOST_SHARED` on host if non-existent.
        - Run Tart with `--dir="shared:$HOST_SHARED:tag=shared"`.
        - Remove VM stop/delete traps. Trap only `rm -rf "$STATE"` on EXIT.
        - Display persistence notice with reconnect, stop, and delete commands.
     4. For `list`: Execute `tart list` filtering for `agent-f`.
     5. For `resume`: Query IP via `tart ip <VM>`, start VM if not running, and open `ssh "${SSH[@]}" -t "agent@$IP"`.
     6. For `stop`: Execute `tart stop <VM>`.
     7. For `delete`: Execute `tart stop <VM>` followed by `tart delete <VM>`.
   - Rationale: Gives user full manual control over persistent VM instances and handles host directory sharing.
   - Dependencies: None.

4. `provision.sh` — `Session Mount Verification and Sanity Checks`
   - Change:
     1. Ensure `/home/agent/workspace` and `/home/agent/shared` exist.
     2. Mount VirtioFS tag `shared` to `/home/agent/shared` if not mounted.
     3. Verify `/dev/kvm` exists.
     4. Verify `docker` and `kvm` group memberships.
   - Rationale: Fast (<2 second) idempotent session initialization.
   - Dependencies: Step 3.

5. `README.md` — `User Documentation`
   - Change:
     1. Update architecture overview: pre-baked base image, persistent VM lifecycle, VirtioFS folder sharing (`$HOME/Documents/VMs/LinuxShared` -> `/home/agent/shared`), Podman container engine.
     2. Document `$HOME/.ssh/agent_jail` setup.
     3. Document all `./session.sh` subcommands (`start`, `list`, `resume`, `stop`, `delete`).
     4. Document `/home/agent/workspace` (isolated) vs `/home/agent/shared` (synced with host).
   - Rationale: Clear operator guidance matching current code behavior.
   - Dependencies: Steps 1–4.

6. `AGENTS.md` — `Repository Guidance for AI Agents`
   - Change:
     1. Update architecture summary: persistent VMs, pre-baked toolchains, dual workspace structure.
     2. Update essential commands to include all `session.sh` subcommands.
     3. Update operational gotchas: manual teardown, host sharing, Podman socket details.
   - Rationale: Ensure AI agents working in this repository have accurate operational instructions.
   - Dependencies: Steps 1–5.

---

## Data and migration plan
No schema migrations are involved. Existing base images (`fedora44-server-base`) can either be rebuilt using the updated `base.pkr.hcl` and `base-update.sh` to benefit from pre-baked tools, or run with `provision.sh` handling runtime fallback.

---

## Test plan

### Syntax and Static Analysis
- Run `bash -n session.sh`
- Run `bash -n provision.sh`
- Run `bash -n base-update.sh`

### Integration and Runtime Verification
1. **Host CLI Subcommands**:
   - Test `./session.sh list` (lists VMs without errors).
   - Test `./session.sh start` argument parsing and host shared directory verification (`$HOME/Documents/VMs/LinuxShared`).
2. **Session Launch & Storage**:
   - Launch session `./session.sh 44`.
   - Verify `/home/agent/workspace` is writable and isolated.
   - Verify `/home/agent/shared` reflects files placed in host `$HOME/Documents/VMs/LinuxShared`:
     - Create file on host: `touch "$HOME/Documents/VMs/LinuxShared/test-from-host.txt"`.
     - In VM: Verify `/home/agent/shared/test-from-host.txt` exists.
     - In VM: `touch /home/agent/shared/test-from-guest.txt`.
     - On host: Verify `$HOME/Documents/VMs/LinuxShared/test-from-guest.txt` exists.
3. **Toolchains & Container Engine**:
   - Inside VM:
     - `go version`
     - `python3 --version`
     - `rustc --version` & `cargo --version`
     - `uv --version`
     - `agy --version`
     - `podman --version`
     - `docker --version` (verifies podman-docker symlink)
     - `podman run --rm hello-world` (or docker run)
4. **Persistence & Lifecycle**:
   - Exit guest SSH session (`exit`).
   - Run `tart list` on host: VM status remains `running`.
   - Run `./session.sh resume <VM>`: connects directly to running VM without re-cloning.
   - Run `./session.sh stop <VM>`: stops the VM.
   - Run `./session.sh delete <VM>`: removes the VM.

---

## Rollout and operations
- **Host Dependencies**: macOS with Apple Silicon, Tart (`brew install cirruslabs/cli/tart`), and Packer.
- **SSH Key**: Ensure key pair exists at `$HOME/.ssh/agent_jail` and `$HOME/.ssh/agent_jail.pub`.
- **Storage Management**: Persistent VMs consume disk in `~/.tart/vms`. Use `./session.sh list` and `./session.sh delete <VM>` to manage host disk space.
- **Host Shared Directory**: `$HOME/Documents/VMs/LinuxShared`.

---

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation | Detection |
|---|---:|---:|---|---|
| VirtioFS mount fails if host directory does not exist | Low | Medium | `session.sh` automatically creates `$HOST_SHARED` before starting Tart | `session.sh` check; `provision.sh` mount verification |
| Disk space accumulation from persistent VMs | High | Medium | Prominently display VM name and manual stop/delete commands; add `./session.sh list` and `delete` | `tart list`, host disk alerts |
| Network failure during external tool download in base build | Medium | High | Use retry logic in curl scripts during `base-update.sh` | Packer build failure logs |
| Non-interactive SSH missing custom PATH | Low | Low | Add exports to both `~/.bashrc` and `~/.bash_profile` | `ssh -i $KEY agent@$IP 'command -v agy'` |

---

## Files likely affected

| File | Action | Reason |
|---|---|---|
| `base.pkr.hcl` | Modify | Pass `fedora_version` to kickstart template; parameterize ISO boot label |
| `base-update.sh` | Modify | Pre-bake all compilers, dev packages, Podman, uv, rustup, agy, and PATH |
| `session.sh` | Modify | Add subcommands (`start`, `list`, `resume`, `stop`, `delete`), VirtioFS sharing with `$HOME/Documents/VMs/LinuxShared`, key path, remove auto-destroy trap |
| `provision.sh` | Modify | Lightweight mount verification and sanity checks for fast session launch |
| `README.md` | Modify | Document persistence, VirtioFS sharing, Podman, toolchains, and subcommands |
| `AGENTS.md` | Modify | Update AI agent operational guidance with full persistent architecture |
