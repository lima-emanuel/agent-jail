packer {
  required_plugins {
    tart = {
      source  = "github.com/cirruslabs/tart"
      version = ">= 1.11.1"
    }
  }
}

variable "fedora_version" {
  type    = string
  default = "44"
}

variable "iso_path" {
  type = string
}

variable "ssh_private_key_file" {
  type = string
}

variable "ssh_public_key_file" {
  type = string
}

variable "kickstart_iso_path" {
  type    = string
  default = ""
}

source "tart-cli" "fedora" {
  vm_name  = "fedora${var.fedora_version}-server-base"
  from_iso = var.kickstart_iso_path != "" ? [abspath(var.iso_path), abspath(var.kickstart_iso_path)] : [abspath(var.iso_path)]

  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 64

  headless       = false
  run_extra_args = ["--nested"]

  ssh_username         = "agent"
  ssh_private_key_file = pathexpand(var.ssh_private_key_file)
  ssh_timeout          = "45m"

  boot_wait = "3s"

  # Interrupt GRUB timeout and boot 'Install Fedora' directly (skips media check)
  boot_command = [
    "<up><enter>"
  ]
}

build {
  sources = ["source.tart-cli.fedora"]

  provisioner "shell" {
    script = "${path.root}/base-update.sh"
  }

  # Boot the installed system's updated kernel before finalizing.
  provisioner "shell" {
    inline            = ["sudo reboot"]
    expect_disconnect = true
  }

  provisioner "shell" {
    pause_before = "15s"
    inline = [
      "uname -r",
      "test -c /dev/kvm",
      "sudo dnf clean all"
    ]
  }
}
