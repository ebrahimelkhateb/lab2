provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "main"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main"
  }
}

# Public Subnets
resource "aws_subnet" "public_a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-b"
  }
}

# Private Subnets
resource "aws_subnet" "private_a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "private-subnet-b"
  }
}

# Route Tables
resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_association_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "public_association_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public-route-table.id
}

# NAT Gateways
resource "aws_eip" "nat_eip_a" {
  vpc = true
}

resource "aws_eip" "nat_eip_b" {
  vpc = true
}

resource "aws_nat_gateway" "NAT_a" {
  subnet_id     = aws_subnet.public_a.id
  allocation_id = aws_eip.nat_eip_a.id

  tags = {
    Name = "gw NAT a"
  }

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "NAT_b" {
  subnet_id     = aws_subnet.public_b.id
  allocation_id = aws_eip.nat_eip_b.id

  tags = {
    Name = "gw NAT b"
  }

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_route_table" "private-route-table_a" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.NAT_a.id
  }

  tags = {
    Name = "private-route-table-a"
  }
}

resource "aws_route_table" "private-route-table_b" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.NAT_b.id
  }

  tags = {
    Name = "private-route-table-b"
  }
}

resource "aws_route_table_association" "private_association_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private-route-table_a.id
}

resource "aws_route_table_association" "private_association_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private-route-table_b.id
}

# Security Groups
resource "aws_security_group" "private_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
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

  tags = {
    Name = "private-sg"
  }
}

resource "aws_security_group" "elb_sg" {
  vpc_id = aws_vpc.main.id

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

  tags = {
    Name = "elb-sg"
  }
}

# AMI Data Source
data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]  # Amazon-owned official AMIs

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]  # Amazon Linux 2
  }
}

# Key Pair
resource "tls_private_key" "my_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "my_key" {
  key_name   = "my-terraform-key"
  public_key = tls_private_key.my_key.public_key_openssh
}

resource "local_file" "private_key" {
  filename        = "my-terraform-key.pem"
  content         = tls_private_key.my_key.private_key_pem
  file_permission = "0600"
}

# EC2 Instances in Private Subnets
resource "aws_instance" "private_instance_a" {
  ami           = data.aws_ami.latest_amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_a.id
  security_groups = [aws_security_group.private_sg.id]
  key_name      = aws_key_pair.my_key.key_name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd nginx
              systemctl start httpd
              systemctl enable httpd
              systemctl start nginx
              systemctl enable nginx
              echo "Hello from Terraform - Instance A" > /var/www/html/index.html
              echo "Hello from Terraform - Instance A" > /usr/share/nginx/html/index.html
              EOF

  tags = {
    Name = "PrivateInstanceA"
  }
}

resource "aws_instance" "private_instance_b" {
  ami           = data.aws_ami.latest_amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_b.id
  security_groups = [aws_security_group.private_sg.id]
  key_name      = aws_key_pair.my_key.key_name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd nginx
              systemctl start httpd
              systemctl enable httpd
              systemctl start nginx
              systemctl enable nginx
              echo "Hello from Terraform - Instance B" > /var/www/html/index.html
              echo "Hello from Terraform - Instance B" > /usr/share/nginx/html/index.html
              EOF

  tags = {
    Name = "PrivateInstanceB"
  }
}

# Load Balancer and Target Group
resource "aws_lb" "my_lb" {
  name               = "my-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  enable_deletion_protection = false

  tags = {
    Name = "my-lb"
  }
}

resource "aws_lb_target_group" "my_target_group" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    interval            = 30
    path                = "/"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "my_lb_listener" {
  load_balancer_arn = aws_lb.my_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}

# Register EC2 Instances with Target Group
resource "aws_lb_target_group_attachment" "instance_a" {
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = aws_instance.private_instance_a.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "instance_b" {
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = aws_instance.private_instance_b.id
  port             = 80
}