terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {}
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type = string
}

variable "public_key" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "admin_cidr_blocks" {
  type    = list(string)
  default = ["10.0.0.0/8"]
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "udap"
    }
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-*-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_vpc" "laravel-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "laravel-subnet" {
  vpc_id                  = aws_vpc.laravel-vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "${var.project_name}-subnet"
  }
}

resource "aws_internet_gateway" "laravel-igw" {
  vpc_id = aws_vpc.laravel-vpc.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route_table" "laravel-rt" {
  vpc_id = aws_vpc.laravel-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.laravel-igw.id
  }

  tags = {
    Name = "${var.project_name}-rt"
  }
}

resource "aws_route_table_association" "laravel-rta" {
  subnet_id      = aws_subnet.laravel-subnet.id
  route_table_id = aws_route_table.laravel-rt.id
}

resource "aws_security_group" "laravel-sg" {
  name        = "${var.project_name}-sg"
  description = "Security group for Laravel app server"
  vpc_id      = aws_vpc.laravel-vpc.id

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_security_group_rule" "laravel-sg-http-ipv4" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.laravel-sg.id
  description       = "Allow HTTP from all IPv4"
}

resource "aws_security_group_rule" "laravel-sg-http-ipv6" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.laravel-sg.id
  description       = "Allow HTTP from all IPv6"
}

resource "aws_security_group_rule" "laravel-sg-https-ipv4" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.laravel-sg.id
  description       = "Allow HTTPS from all IPv4"
}

resource "aws_security_group_rule" "laravel-sg-https-ipv6" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.laravel-sg.id
  description       = "Allow HTTPS from all IPv6"
}

resource "aws_security_group_rule" "laravel-sg-ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.admin_cidr_blocks
  security_group_id = aws_security_group.laravel-sg.id
  description       = "Allow SSH from admin CIDR blocks only"
}

resource "aws_security_group_rule" "laravel-sg-egress-http" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.laravel-sg.id
  description       = "Allow outbound HTTP for apt/composer"
}

resource "aws_security_group_rule" "laravel-sg-egress-https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.laravel-sg.id
  description       = "Allow outbound HTTPS for apt/composer"
}

resource "aws_key_pair" "laravel-key" {
  key_name   = "${var.project_name}-key"
  public_key = var.public_key

  tags = {
    Name = "${var.project_name}-key"
  }
}

resource "aws_instance" "laravel-app-server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.laravel-subnet.id
  vpc_security_group_ids = [aws_security_group.laravel-sg.id]
  key_name               = aws_key_pair.laravel-key.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-app"
  }
}

resource "aws_eip" "laravel-eip" {
  instance = aws_instance.laravel-app-server.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }

  depends_on = [aws_internet_gateway.laravel-igw]
}

output "instance_public_ip" {
  value       = aws_eip.laravel-eip.public_ip
  description = "Static public IP of the Laravel app server"
}

output "app_url" {
  value       = "http://${aws_eip.laravel-eip.public_ip}"
  description = "Public URL of the Laravel application"
}