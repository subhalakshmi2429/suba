provider "aws" {
  region = "ap-south-1"
}

# Fetch existing VPC by name
data "aws_vpc" "custom" {
  filter {
    name   = "tag:Name"
    values = ["project-vpc"]
  }
}

# Fetch private subnets in the VPC
data "aws_subnets" "custom" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.custom.id]
  }
}

# Fetch custom security group
data "aws_security_group" "ecs_sg" {
  filter {
    name   = "group-name"
    values = ["ECS-SG"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.custom.id]
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "private_cluster" {
  name = "private-test-cluster"
}

# ECR Repository
resource "aws_ecr_repository" "private_repo" {
  name = "private-flask-repo"
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "private_task" {
  family                   = "private-test-task"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name  = "my-final-test-container",
    image = "dummy", # Overwritten in imagedefinitions.json
    essential = true,
    portMappings = [{
      containerPort = 5000,
      hostPort      = 5000
    }]
  }])
}

# ECS Service
resource "aws_ecs_service" "private_service" {
  name            = "private-test-service"
  cluster         = aws_ecs_cluster.private_cluster.id
  task_definition = aws_ecs_task_definition.private_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.custom.ids
    security_groups = [data.aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }
}

# ------------------------------------------
# IAM Role for CodeBuild
# ------------------------------------------

resource "aws_iam_role" "codebuild_service_role" {
  name = "codebuild-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "codebuild.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_ecr_policy" {
  role       = aws_iam_role.codebuild_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "codebuild_basic_policy" {
  role       = aws_iam_role.codebuild_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess"
}
