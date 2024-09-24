packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "hardened-ami" {
  ami_name      = "hardened-ami-{{timestamp}}"
  instance_type = "t2.medium"
  region        = "us-west-2"
  source_ami_filter {
    filters = {
      name                = "amzn2-ami-hvm-*-x86_64-gp2"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }
  ssh_username = "ubuntu"
}

build {
  sources = [
    "source.amazon-ebs.hardened-ami"
  ]

  provisioner "shell" {
    inline = [
      "sudo apt update -y",
      "sudo apt upgrade -y"
    ]
  }

  provisioner "ansible" {
    playbook_file = "./hardening.yml"
  }
}