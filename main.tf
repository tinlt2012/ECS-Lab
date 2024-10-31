
resource "aws_vpc" "main" {
  cidr_block = "172.16.0.0/16"
  tags = {
    Name = "main-vpc"
  }
}
resource "aws_subnet" "public1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.1.0/24"
  availability_zone = "us-east-1a"  
  tags = {
    Name = "public-subnet-1"
  }
}
resource "aws_subnet" "public2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.3.0/24"
  availability_zone = "us-east-1b"  
  tags = {
    Name = "public-subnet-2"
  }
}
resource "aws_subnet" "private1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.2.0/24"
  availability_zone = "us-east-1a"  
  tags = {
    Name = "private-subnet-1"
  }
}
resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.4.0/24"
  availability_zone = "us-east-1b"  
  tags = {
    Name = "private-subnet-2"
  }
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-internet-gateway"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public-route-table"
  }
}
resource "aws_route_table_association" "public_subnet1_assoc" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public_subnet2_assoc" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "private-route-table"
  }
}
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
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
  
  tags = {
    Name = "web-sg"
  }
}
data "aws_ami" "latest" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]  
  }
}

resource "aws_instance" "nat" {
  ami                    = data.aws_ami.latest.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  source_dest_check = false
  associate_public_ip_address = true
  user_data = <<-EOF
                #!/bin/bash
                sudo yum update -y
                sudo yum install iptables-services -y
                sudo systemctl enable iptables
                sudo systemctl start iptables
                sudo echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/custom-ip-forwarding.conf
                sudo sysctl -p /etc/sysctl.d/custom-ip-forwarding.conf
                sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
                sudo /sbin/iptables -F FORWARD
                sudo service iptables save
              EOF
  tags = {
    Name = "nat_instance"
  }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
  instance = aws_instance.nat.id
  tags = {
    Name = "nat-eip"
  }
}
resource "aws_route" "nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}
resource "aws_route_table_association" "private_subnet1_assoc" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private_subnet2_assoc" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private.id
}


data "aws_caller_identity" "current" {}

# Tạo ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "Terraform-cluster"
}
resource "aws_ecs_task_definition" "tinlt_task" {
  family                   = "Tinlt_terraform"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "3072"
  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/nginx-php:latest"
      essential = true
      cpu       = 0
      portMappings = [
        {
          name          = "nginx-80-tcp"
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      environment = [
        {
          name  = "MYSQL_DATABASE"
          value = "dbname"
        },
        {
          name  = "MYSQL_PASSWORD"
          value = "dbpassword"
        },
        {
          name  = "MYSQL_HOST"
          value = "0.0.0.0"
        },
        {
          name  = "MYSQL_USER"
          value = "dbuser"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group          = "/ecs/Tinlt"
          mode                   = "non-blocking"
          awslogs-create-group   = "true"
          max-buffer-size        = "25m"
          awslogs-region         = "us-east-1"
          awslogs-stream-prefix  = "ecs"
        }
      }
    },
    {
      name      = "mysql"
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/mysql:latest"
      essential = false
      cpu       = 0
      portMappings = [
        {
          name          = "mysql-3306-tcp"
          containerPort = 3306
          hostPort      = 3306
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "MYSQL_DATABASE"
          value = "dbname"
        },
        {
          name  = "MYSQL_PASSWORD"
          value = "dbpassword"
        },
        {
          name  = "MYSQL_ROOT_PASSWORD"
          value = "yourpassword"
        },
        {
          name  = "MYSQL_USER"
          value = "dbuser"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group          = "/ecs/Tinlt/mysql"
          mode                   = "non-blocking"
          awslogs-create-group   = "true"
          max-buffer-size        = "25m"
          awslogs-region         = "us-east-1"
          awslogs-stream-prefix  = "ecs"
        }
      }
    }
  ])
  task_role_arn      = "arn:aws:iam::036855062023:role/ecsTaskExecutionRole"
  execution_role_arn = "arn:aws:iam::036855062023:role/ecsTaskExecutionRole"
  runtime_platform {
    cpu_architecture         = "ARM64"
    operating_system_family  = "LINUX"
  }
}
#Tạo ALB
resource "aws_lb" "ecs_lb" {
  name               = "ecs-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public1.id, aws_subnet.public2.id]

  tags = {
    Name = "ecs-alb"
  }
}
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id

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

  tags = {
    Name = "alb-security-group"
  }
}
resource "aws_lb_target_group" "ecs_tg" {
  name     = "ecs-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "ecs-target-group"
  }
}
resource "aws_lb_listener" "ecs_lb_listener" {
  load_balancer_arn = aws_lb.ecs_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }

  tags = {
    Name = "ecs-lb-listener"
  }
}
# Tạo ECS Service
resource "aws_ecs_service" "all_service" {
  name            = "terraform"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.tinlt_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = [aws_subnet.public1.id, aws_subnet.public2.id]
    security_groups = [aws_security_group.web_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "nginx"
    container_port   = 80
    
  } 
  deployment_controller {
    type = "ECS"        
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  depends_on = [aws_lb_listener.ecs_lb_listener]
}