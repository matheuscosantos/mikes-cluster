provider "aws" {
  region = var.region
}

# -- ecr

resource "aws_ecr_repository" "ecr_repository" {
  name = "${var.name}_app"
}

# -- private network

resource "aws_vpc" "private_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "${var.name}_private_vpc"
  }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id     = aws_vpc.private_vpc.id
  cidr_block = "10.0.0.0/20"
  availability_zone = "${var.region}a"

  tags = {
    Name = "${var.name}_private_subnet_a"
  }
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id     = aws_vpc.private_vpc.id
  cidr_block = "10.0.16.0/20"
  availability_zone = "${var.region}b"

  tags = {
    Name = "${var.name}_private_subnet_b"
  }
}

resource "aws_subnet" "private_subnet_c" {
  vpc_id     = aws_vpc.private_vpc.id
  cidr_block = "10.0.32.0/20"
  availability_zone = "${var.region}c"

  tags = {
    Name = "${var.name}_private_subnet_c"
  }
}

# -- security group

resource "aws_security_group" "security_group" {
  name        = "${var.name}_security_group"
  description = "Permissive security group for educational purposes"
  vpc_id      = aws_vpc.private_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -- ecs cluster

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.name}_cluster"
}

# -- creating launch template

data "aws_ami" "amazon_linux_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.name}_ec2_role"
  assume_role_policy = file("iam/role/ec2_role.json")
}

resource "aws_iam_policy_attachment" "ec2_role_ec2_policy_attachment" {
  name       = "${var.name}_ec2_role_ec2_policy_attachment"
  roles      = [aws_iam_role.ec2_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_policy_attachment" "ec2_role_ssm_policy_attachment" {
  name       = "${var.name}_ec2_role_ssm_policy_attachment"
  roles      = [aws_iam_role.ec2_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "${var.name}_instance_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_launch_template" "ec2_launch_configuration" {
  image_id      = data.aws_ami.amazon_linux_ami.id
  instance_type = "t2.micro"
  name_prefix   = "${var.name}_launch_configuration"

  vpc_security_group_ids = [aws_security_group.security_group.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.instance_profile.name
  }

  user_data = base64encode(file("user_data/launch_template.sh"))
}

# -- creating autoscaling group

resource "aws_autoscaling_group" "ec2_autoscaling_group" {
  name                      = "${var.name}_autoscaling_group"

  vpc_zone_identifier        = [aws_subnet.private_subnet_a.id]

  desired_capacity          = 1
  min_size                  = 1
  max_size                  = 1

  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.ec2_launch_configuration.id
    version = "$Latest"
  }
}

# -- creating capacity providers

resource "aws_ecs_capacity_provider" "ec2_capacity_provider" {
  name                      = "${var.name}_capacity_provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ec2_autoscaling_group.arn
  }
}

resource "aws_ecs_cluster_capacity_providers" "ecs_cluster_capacity_providers" {
  cluster_name = aws_ecs_cluster.ecs_cluster.name

  capacity_providers = [
    aws_ecs_capacity_provider.ec2_capacity_provider.name
  ]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ec2_capacity_provider.name
  }
}
