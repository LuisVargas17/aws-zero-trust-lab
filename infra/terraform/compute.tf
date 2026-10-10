data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  bootstrap_user_data = <<-BASH
    #!/bin/bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y awscli ca-certificates curl unzip jq
    systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || true
    systemctl enable --now amazon-ssm-agent || true
  BASH
}

resource "aws_instance" "frontend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.frontend_instance_type
  subnet_id                   = aws_subnet.frontend_public.id
  private_ip                  = var.frontend_private_ip
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  iam_instance_profile        = aws_iam_instance_profile.frontend.name
  user_data                   = local.bootstrap_user_data
  user_data_replace_on_change = true
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  tags = { Name = "${var.project_name}-frontend-ec2" }
  depends_on = [aws_iam_role_policy_attachment.frontend_ssm, aws_route_table_association.frontend_public]
}

resource "aws_eip" "frontend" {
  domain   = "vpc"
  instance = aws_instance.frontend.id
  tags     = { Name = "${var.project_name}-frontend-eip" }
}

resource "aws_instance" "backend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.backend_instance_type
  subnet_id                   = aws_subnet.backend_private.id
  private_ip                  = var.backend_private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.backend.id]
  iam_instance_profile        = aws_iam_instance_profile.backend.name
  user_data                   = local.bootstrap_user_data
  user_data_replace_on_change = true
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  tags = { Name = "${var.project_name}-backend-ec2" }
  depends_on = [aws_iam_role_policy_attachment.backend_ssm, aws_route_table_association.backend_private, aws_route_table_association.backend_nat_public, aws_route.frontend_to_backend, aws_route.backend_to_frontend]
}

resource "aws_route53_record" "frontend_a" {
  count   = var.route53_zone_id != "" && var.domain_name != "" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [aws_eip.frontend.public_ip]
}
