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
  default = "ami-05134c8ef96964280"  // Ubuntu 22.04 LTS in us-west-2
}

locals {
  app_name = "hardened-ubuntu-ec2"
}

source "amazon-ebs" "hardened" {
  ami_name      = "${local.app_name}-{{timestamp}}"
  instance_type = "t2.medium"
  region        = "us-west-2"
  source_ami    = "${var.ami_id}"
  ssh_username  = "ubuntu"  // Changed to ubuntu for Ubuntu AMIs
  tags = {
    Env  = "prod"
    Name = "${local.app_name}"
  }
}

build {
  sources = ["source.amazon-ebs.hardened"]

  provisioner "ansible" {
    playbook_file = "ansible/harden-ubuntu-ec2.yaml"
    extra_arguments = [
      "--extra-vars", "ami_id=${var.ami_id}",
      "--scp-extra-args", "'-O'",
      "--ssh-extra-args", "-o IdentitiesOnly=yes -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"
    ]
  }
  
  post-processor "manifest" {
    output = "manifest.json"
    strip_path = true
  }
}