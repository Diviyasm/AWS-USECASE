#Provider
provider "aws" {
  region = "us-west-2"
}
# VPC
resource "aws_vpc" "my_app_vpc" {
  cidr_block = "10.0.0.0/16"
  
}

# Subnets
resource "aws_subnet" "my_public_subnet_1" {
  vpc_id                  = aws_vpc.my_app_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
  
}

resource "aws_subnet" "my_public_subnet_2" {
  vpc_id                  = aws_vpc.my_app_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-west-2b"
  map_public_ip_on_launch = true

}

resource "aws_subnet" "my_private_subnet" {
  vpc_id                  = aws_vpc.my_app_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-west-2a"
}

# Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_app_vpc.id
}

#Route Table
resource "aws_route_table" "my_public_route_table" {
  vpc_id = aws_vpc.my_app_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }
}

#Associate Route table with Subnets
resource "aws_route_table_association" "my_public_subnet_1" {
  subnet_id      = aws_subnet.my_public_subnet_1.id
  route_table_id = aws_route_table.my_public_route_table.id
}

resource "aws_route_table_association" "my_public_subnet_2" {
  subnet_id      = aws_subnet.my_public_subnet_2.id
  route_table_id = aws_route_table.my_public_route_table.id
}

# Security Groups
resource "aws_security_group" "my_public_sg" {
  vpc_id = aws_vpc.my_app_vpc.id
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
}

resource "aws_security_group" "my_private_sg" {
  vpc_id = aws_vpc.my_app_vpc.id
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.my_public_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
}

# Launch_template
resource "aws_launch_template" "my_app_launch_template" {
  name          = "my-app-launch-template"
  instance_type = "t2.micro"
  image_id      = "ami-055e3d4f0bbeb5878"
  iam_instance_profile {
    name = aws_iam_instance_profile.my_app_role_profile.name
  }
  vpc_security_group_ids = [aws_security_group.my_public_sg.id]
} 


 # Autoscaling Group
resource "aws_autoscaling_group" "my_app_asg" {
  desired_capacity     = 2
  max_size             = 5
  min_size             = 2
  vpc_zone_identifier  = [aws_subnet.my_public_subnet_1.id, aws_subnet.my_public_subnet_2.id]
  launch_template {
    id      = aws_launch_template.my_app_launch_template.id
    version = "$Latest"
  }
}

# Single EC2 Instance
resource "aws_instance" "my_private_instance" {
  ami           = "ami-055e3d4f0bbeb5878" 
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.my_private_subnet.id
  vpc_security_group_ids = [aws_security_group.my_private_sg.id]
  
}

# Load Balancers
resource "aws_lb" "my_app_alb" {
  name            = "my-app-alb"
  internal        = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.my_public_sg.id]
  subnets         = [aws_subnet.my_public_subnet_1.id, aws_subnet.my_public_subnet_2.id]
}

resource "aws_lb" "my_app_nlb" {
  name            = "my-app-nlb"
  internal        = true
  load_balancer_type = "network"
  subnets         = [aws_subnet.my_private_subnet.id]
}

# Target Group for Application Load Balancer
resource "aws_lb_target_group" "my_alb_target_group" {
  name        = "my-alb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.my_app_vpc.id
  target_type = "instance"
}

# Listener for Application Load Balancer
resource "aws_lb_listener" "my_alb_listener" {
  load_balancer_arn = aws_lb.my_app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_alb_target_group.arn
  }
}

# Autoscaling Attachment
resource "aws_autoscaling_attachment" "my_asg_alb_attachment" {
  autoscaling_group_name = aws_autoscaling_group.my_app_asg.name
  lb_target_group_arn = aws_lb_target_group.my_alb_target_group.arn
}

# Target Group for Network Load Balancer
resource "aws_lb_target_group" "my_nlb_target_group" {
  name        = "my-nlb-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.my_app_vpc.id
  target_type = "instance"
}

# Listener for Network Load Balancer
resource "aws_lb_listener" "my_nlb_listener" {
  load_balancer_arn = aws_lb.my_app_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_nlb_target_group.arn
  }
}

# Target Group Attachment for Network Load Balancer
# Private EC2 Instance
resource "aws_lb_target_group_attachment" "my_nlb_instance_attachment" {
  target_group_arn = aws_lb_target_group.my_nlb_target_group.arn
  target_id        = aws_instance.my_private_instance.id
  port             = 80
}


# S3 Bucket
resource "aws_s3_bucket" "my_app_bucket" {
  bucket = "diviya-bucket"
}

# S3 Bucket Ownership Controls
resource "aws_s3_bucket_ownership_controls" "my_app_bucket_ownership_controls" {
  bucket = aws_s3_bucket.my_app_bucket_1.id

  rule {
    object_ownership = "BucketOwnerPreferred"  # Object ownership set to bucket owner preferred
  }
}

# S3 Bucket ACL
resource "aws_s3_bucket_acl" "my_app_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.my_app_bucket_ownership_controls]  # Ensure ownership controls are created first

  bucket = aws_s3_bucket.my_app_bucket_1.id
  acl    = "private"  # Apply private ACL
}

# S3 versioning
resource "aws_s3_bucket_versioning" "versioning_bucket" {
  bucket = aws_s3_bucket.my_app_bucket_1.id
  versioning_configuration {
    status = "Enabled"
  }
}

# IAM Role for ec2
resource "aws_iam_role" "my_app_role" {
  name = "my-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# IAM Policy for S3 Access
resource "aws_iam_policy" "my_bucket_access_policy" {
  name        = "my-s3-access-policy"
  description = "Provide full access to S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:*"],
        Resource = [
          aws_s3_bucket.my_app_bucket.arn,
          "${aws_s3_bucket.my_app_bucket.arn}/*"
        ]
      }
    ]
  })
}

#Attaching IAM Role Policy
resource "aws_iam_role_policy_attachment" "my_attach_s3_policy" {
  role       = aws_iam_role.my_app_role.name
  policy_arn = aws_iam_policy.my_bucket_access_policy.arn
}
# IAM Instance Profile
resource "aws_iam_instance_profile" "my_app_role_profile" {
  name = "my-app-role-profile-2"
  role = aws_iam_role.my_app_role.name
}
