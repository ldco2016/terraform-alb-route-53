# ==========================================
# 1. NETWORKING INFRASTRUCTURE (VPC)
# ==========================================

resource "aws_vpc" "lab_vpc" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true
    tags = {Name = "lab-vpc"}
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.lab_vpc.id
    tags = {Name = "lab-igw"}
} 

resource "aws_subnet" "pub_subnet_a" {
    vpc_id = aws_vpc.lab_vpc.id
    cidr_block = "10.0.0.0/24"
    availability_zone = "us-east-1a"
    map_public_ip_on_launch = true
    tags = {Name = "pub-subnet-a"}
}

resource "aws_subnet" "pub_subnet_b" {
    vpc_id = aws_vpc.lab_vpc.id
    cidr_block = "10.0.0.0/24"
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = true
    tags = {Name = "pub-subnet-b"}
}

resource "aws_route_table" "pub_rt" {
    vpc_id = aws_vpc.lab_vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags = {Name = "public-route-table"}
}

resource "aws_route_table_association" "a" {
    subnet_id = aws_subnet.pub_subnet_a.id
    route_table_id = aws_route_table.pub_rt.id
}

resource "aws_route_table_association" "b" {
    subnet_id = aws_subnet.pub_subnet_b.id
    route_table_id = aws_route_table.pub_rt.id
}

# ==========================================
# 2. SECURITY GROUPS
# ==========================================

resource "aws_security_group" "alb_sg" {
    name = "alb-security-group"
    description = "Allow inbound HTTP traffic to ALB"
    vpc_id = aws_vpc.lab_vpc.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"] # For a strict lab, swap this with your home IP: "your.home.ip.address/32"
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "ec2-sg" {
    name = "ec2-security-group"
    description = "Allow HTTP traffic only from ALB"
    vpc_id = aws_vpc.lab_vpc.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        security_groups = [aws_security_group.alb_sg.id] # Strict tiering
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# ==========================================
# 3. COMPUTE (EC2 INSTANCES) & BOOTSTRAP
# ==========================================

# Dynamically pull the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
    most_recent = true
    owners = ["amazon"]
    filter {
        name = "name"
        values = ["al2023-ami-202*x86_64"]
    }
}

resource "aws_instance" "server_a" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro" # Or t3.micro depending on preference/region
  subnet_id              = aws_subnet.pub_subnet_a.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from Server A (AZ-A)</h1>" > /var/www/html/index.html
              EOF

  tags = { Name = "web-server-a" }
}

resource "aws_instance" "server_b" {
    ami = data.aws_ami.amazon_linux_2023.id 
    instance_type = "t2.micro"
    subnet_id = aws_subnet.pub_subnet_b.id
    vpc_security_group_ids = [aws_security_group.ec2-sg.id]

    user_data = <<-EOF
              #!/bin/bash
              dnf install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from Server A (AZ-A)</h1>" > /var/www/html/index.html
              EOF

    tags = { Name = "web-server-b" }
}

# ==========================================
# 4. LOAD BALANCING (ALB)
# ==========================================

resource "aws_lb" "lab_alb" {
    name = "public-lab-alb"
    internal = false
    load_balancer_type = "application"
    security_groups = [aws_security_group.alb_sg.id]
    subnets = [aws_subnet.pub_subnet_a.id, aws_subnet.pub_subnet_b.id]
}

resource "aws_lb_target_group" "alb-tg" {
    name = "alb-target-group"
    port = 80
    protocol = "HTTP"
    vpc_id = aws_vpc.lab_vpc.id

    health_check {
      path = "/"
      port = "80"
      protocol = "HTTP"
      healthy_threshold = 2
    }
}