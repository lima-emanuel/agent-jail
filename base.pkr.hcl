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

source "tart-cli" "fedora" {
  vm_name  = "fedora${var.fedora_version}-server-base"
  from_iso = [abspath(var.iso_path)]

  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 64

  headless = false
  run_extra_args = ["--nested"]

  ssh_username         = "agent"
  ssh_private_key_file = pathexpand(var.ssh_private_key_file)
  ssh_timeout          = "45m"

  http_content = {
    "/ks.cfg" = templatefile(
      "${path.root}/kickstart.ks.pkrtpl",
      {
        fedora_version = var.fedora_version
        ssh_public_key = trimspace(
          file(pathexpand(var.ssh_public_key_file))
        )
      }
    )
  }

  boot_wait = "5s"

  # Fedora Server netinstall ISO, UEFI GRUB menu.
  # Test visually on the first build; exact device/path can vary by ISO.
  boot_command = [
    "c<wait>",
    "linux (cd0)/images/pxeboot/vmlinuz ",
    "inst.stage2=hd:LABEL=Fedora-S-dvd-aarch64-${var.fedora_version} ",
    "inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg ",
    "ip=dhcp rd.neednet=1<enter>",
    "initrd (cd0)/images/pxeboot/initrd.img<enter>",
    "boot<enter>"
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
