packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "ami_id" {
  type    = string
  default = "ami-05134c8ef96964280"
}

variable "efs_mount_point" {
  type    = string
  default = ""
}

locals {
  app_name = "proxy-server"
}

source "amazon-ebs" "proxy" {
  ami_name      = "${local.app_name}"
  instance_type = "t2.medium"
  region        = "us-west-2"
  availability_zone = "us-west-2a"
  source_ami = "${var.ami_id}"
  ssh_username = "ubuntu"
  tags = {
    Env = "dev"
    Name = "${local.app_name}"
  }
}

build {
  sources = ["source.amazon-ebs.proxy"]

  provisioner "shell" {
    inline = [
      "sudo apt update -y",
      "sudo apt upgrade -y"
    ]
  }

  provisioner "ansible" {
    playbook_file = "ansible/hardening.yml"
  }
}
