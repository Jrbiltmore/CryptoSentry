provider "aws" {
  region = "us-west-2"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Subnets
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

# Security Groups
resource "aws_security_group" "api_sg" {
  name_prefix = "api-sg"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "blockchain_sg" {
  name_prefix = "blockchain-sg"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30303
    to_port     = 30303
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30303
    to_port     = 30303
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instances
resource "aws_instance" "api_instance" {
  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public.id
  security_groups = [aws_security_group.api_sg.name]

  tags = {
    Name = "CryptoSentry-API"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install docker -y
              service docker start
              usermod -a -G docker ec2-user
              docker run -d -p 80:80 -p 443:443 mydockerhubuser/cryptosentry-api:latest
              EOF
}

resource "aws_instance" "blockchain_node" {
  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
  instance_type = "t2.medium"
  subnet_id     = aws_subnet.public.id
  security_groups = [aws_security_group.blockchain_sg.name]

  tags = {
    Name = "CryptoSentry-Blockchain-Node"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install docker -y
              service docker start
              usermod -a -G docker ec2-user
              docker run -d -p 30303:30303 -p 30303:30303/udp mydockerhubuser/cryptosentry-blockchain-node:latest
              EOF
}

# Load Balancers
resource "aws_elb" "api_elb" {
  name               = "crypto-sentry-api-elb"
  availability_zones = ["us-west-2a", "us-west-2b"]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  listener {
    instance_port     = 443
    instance_protocol = "HTTPS"
    lb_port           = 443
    lb_protocol       = "HTTPS"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  instances = [aws_instance.api_instance.id]

  tags = {
    Name = "CryptoSentry-API-ELB"
  }
}

resource "aws_elb" "blockchain_elb" {
  name               = "crypto-sentry-blockchain-elb"
  availability_zones = ["us-west-2a", "us-west-2b"]

  listener {
    instance_port     = 30303
    instance_protocol = "TCP"
    lb_port           = 30303
    lb_protocol       = "TCP"
  }

  health_check {
    target              = "TCP:30303"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  instances = [aws_instance.blockchain_node.id]

  tags = {
    Name = "CryptoSentry-Blockchain-ELB"
  }
}

# Outputs
output "api_url" {
  value = aws_elb.api_elb.dns_name
}

output "blockchain_node_url" {
  value = aws_elb.blockchain_elb.dns_name
}
