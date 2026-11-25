terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

locals {
  name = "acs730-a1-${var.environment}"
  tags = {
    Project     = "acs730"
    Lab         = "assignment1"
    Environment = var.environment
  }
}

# Latest Amazon Linux 2023, looked up by AMI name.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }
}

# Task 6: Terraform READS this parameter. It never creates it. You create it
# once, by hand, with `aws ssm put-parameter` (see Part 1).
data "aws_ssm_parameter" "db_password" {
  name            = "/acs730/${var.environment}/db_password"
  with_decryption = true
}

resource "aws_security_group" "web" {
  name        = "${local.name}-sg"
  description = "ACS730 Assignment 1 ${var.environment} web servers - port 80 in, nothing else"

  # There is deliberately no port 22 rule. Access is by Session Manager.
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-sg" })
}

resource "aws_instance" "web" {
  count                  = var.instance_count
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = var.instance_profile

  tags = merge(local.tags, { Name = "${local.name}-web-${count.index}" })
}

# Task 7: an alarm on a metric an idle instance still reports.
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count               = var.instance_count
  alarm_name          = "${local.name}-cpu-high-${count.index}"
  alarm_description   = "Average CPU above ${var.cpu_alarm_threshold}% for two 5-minute periods"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.web[count.index].id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"

  tags = local.tags
}
