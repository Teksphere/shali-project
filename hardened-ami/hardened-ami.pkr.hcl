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
  source_ami    = "${var.ami_id}"
  ssh_username  = "ubuntu"
  
  # Option 1: Use ssh_keypair_name with ssh_private_key_file
  ssh_keypair_name = "us-west-key"
  ssh_private_key_file = "C:\Users\USER\Desktop\devops\keys/us-west-key.pem"
  
  # Option 2: Use ssh_agent_auth
  # ssh_agent_auth = true

  tags = {
    Env  = "dev"
    Name = "${local.app_name}"
  }
}

build {
  sources = ["source.amazon-ebs.proxy"]

  provisioner "shell" {
    inline = [
      "sudo apt update -y",
      "sudo apt upgrade -y",
      "sudo apt install -y python3"
    ]
  }

  provisioner "ansible" {
    playbook_file   = "ansible/hardening.yml"
    extra_arguments = ["--verbose"]
    ansible_env_vars = ["ANSIBLE_STDOUT_CALLBACK=debug"]
  }
}