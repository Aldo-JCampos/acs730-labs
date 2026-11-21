packer {
  # Packer has shipped no built-in builders since 1.7. Without this,
  # init fetches nothing and validate says: Unknown builder type.
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.3"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1.1"
    }
  }
}

# Every variable needs a default: validate does not read your shell
# environment, and an unset variable is a hard validation failure.
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_name_prefix" {
  type    = string
  default = "acs730-lab6-web"
}

variable "playbook_file" {
  type    = string
  default = "../ansible/site.yml"
}

locals {
  stamp = formatdate("YYYYMMDD-hhmmss", timestamp())
}

source "amazon-ebs" "web" {
  region        = var.aws_region
  instance_type = var.instance_type
  ssh_username  = "ec2-user"
  ami_name      = "${var.ami_name_prefix}-${local.stamp}"

  # A filter, not a data source: filters resolve at BUILD time, so
  # validate stays offline and passes with no credentials.
  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-kernel-6.1-x86_64"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  tags = {
    Name    = "${var.ami_name_prefix}-${local.stamp}"
    Project = "acs730"
    Lab     = "lab6"
    Role    = "web"
  }
}

build {
  name    = "golden-web"
  sources = ["source.amazon-ebs.web"]

  provisioner "ansible" {
    playbook_file = "${path.root}/${var.playbook_file}"
    user          = "ec2-user"

    # Talk straight to the build instance instead of through Packer's
    # SSH adapter. This is what works with current OpenSSH.
    use_proxy = false

    ansible_env_vars = ["ANSIBLE_HOST_KEY_CHECKING=False"]

    extra_arguments = [
      "--scp-extra-args", "'-O'",
      "--extra-vars", "build_tag=golden-ami"
    ]
  }

  # Runs after the role, so /opt/acs730-web already exists and nothing
  # the role manages is overwritten.
  provisioner "file" {
    source      = "${path.root}/files/index.html"
    destination = "/tmp/baked.html"
  }

  provisioner "shell" {
    inline = [
      "sudo install -o acs730web -g acs730web -m 0644 /tmp/baked.html /opt/acs730-web/baked.html"
    ]
  }

  post-processor "manifest" {
    output = "packer-manifest.json"
  }
}
