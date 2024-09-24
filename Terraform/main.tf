# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "SHALI-VPC"
  }
}

# Create public subnets
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "SHALI-Public-Subnet-${count.index + 1}"
  }
}

# Create private subnets
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "SHALI-Private-Subnet-${count.index + 1}"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "SHALI-IGW"
  }
}

# Create NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "SHALI-NAT-Gateway"
  }
}

# Allocate Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "SHALI-NAT-EIP"
  }
}

# Create route tables and associate with subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "SHALI-Public-Route-Table"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "SHALI-Private-Route-Table"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Create security group for proxy server
resource "aws_security_group" "proxy" {
  name        = "proxy-sg"
  description = "Security group for proxy server"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3128
    to_port     = 3128
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SHALI-Proxy-SG"
  }
}

# Create proxy server EC2 instance
resource "aws_instance" "proxy" {
  ami           = var.ami_id # Replace with your hardened AMI ID
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.proxy.id]
  subnet_id              = aws_subnet.public[0].id

  tags = {
    Name = "SHALI-Proxy-Server"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y squid
              systemctl enable squid
              systemctl start squid
              EOF
}

# Create security group for EC2 instances
resource "aws_security_group" "ec2" {
  name        = "ec2-sg"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.proxy.id]
  }

  tags = {
    Name = "SHALI-EC2-SG"
  }
}

# Create EC2 instances
resource "aws_instance" "app_servers" {
  count         = 2
  ami           = "ami-0c55b159cbfafe1f0" # Replace with your hardened AMI ID
  instance_type = "t2.micro"
  key_name      = "your-key-pair-name"

  vpc_security_group_ids = [aws_security_group.ec2.id]
  subnet_id              = aws_subnet.private[count.index].id

  tags = {
    Name = "SHALI-App-Server-${count.index + 1}"
  }

  user_data = <<-EOF
              #!/bin/bash
              echo "http_proxy=http://${aws_instance.proxy.private_ip}:3128" >> /etc/environment
              echo "https_proxy=http://${aws_instance.proxy.private_ip}:3128" >> /etc/environment
              source /etc/environment
              # Add other setup commands here
              EOF
}

# Create security group for ALB
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

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
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = {
    Name = "SHALI-ALB-SG"
  }
}

# Create Application Load Balancer
resource "aws_lb" "main" {
  name               = "shali-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "SHALI-ALB"
  }
}

# Create ALB target group
resource "aws_lb_target_group" "main" {
  name     = "shali-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

# Attach EC2 instances to the target group
resource "aws_lb_target_group_attachment" "main" {
  count            = 2
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.app_servers[count.index].id
  port             = 80
}

# Create ALB listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# Create IAM role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "shali-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies to the EC2 role
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.ec2_role.name
}

# Create IAM instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "shali-ec2-profile"
  role = aws_iam_role.ec2_role.name
}
