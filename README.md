# Agent Jail

MacOS Agent Jail using Tart. The workflow is:

Fedora Server aarch64 ISO + Kickstart + Packer
│
▼
Updated, reusable Fedora base
│
▼
Clone → boot with --nested → provision.sh
│
▼
Coding-agent session
│
▼
Export work → delete clone (optional)

## Usage

Initialize Packer and build from your downloaded Fedora 44 Server aarch64:

```bash
packer init base.pkr.hcl

packer build \
  -var 'fedora_version=44' \
  -var "iso_path=$HOME/Downloads/YOUR-FEDORA-44-SERVER-AARCH64.iso" \
  -var "ssh_private_key_file=$HOME/.ssh/agent_jail" \
  -var "ssh_public_key_file=$HOME/.ssh/agent_jail.pub" \
  base.pkr.hcl
```

Launch a session:

```bash
chmod +x session.sh
./session.sh 44
```

When Fedora 45 launches, redo with `fedora_version=45` and `./session.sh 45`.
