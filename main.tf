provider "aws" {
  region = "ap-south-1"
}

# ------------------------------------------
# DATA SOURCES
# ------------------------------------------

data "aws_vpc" "custom" {
  filter {
    name   = "tag:Name"
    values = ["project-vpc"]
  }
}

data "aws_subnets" "custom" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.custom.id]
  }
}

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

# ------------------------------------------
# ECS CLUSTER
# ------------------------------------------

resource "aws_ecs_cluster" "private_cluster" {
  name = "private-test-cluster"
}

# ------------------------------------------
# ECR REPOSITORY
# ------------------------------------------

data "aws_ecr_repository" "existing_repo" {
  name = "private-flask-repo"
  count = 0
  # only used when resource fails to create
}

resource "aws_ecr_repository" "private_repo" {
  name = "private-flask-repo"
  lifecycle {
    ignore_errors = true
  }
}

# ------------------------------------------
# IAM ROLE FOR ECS TASK EXECUTION
# ------------------------------------------

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

# ------------------------------------------
# ECS TASK DEFINITION
# ------------------------------------------

resource "aws_ecs_task_definition" "private_task" {
  family                   = "private-test-task"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name  = "my-final-test-container",
    image = "dummy", # Will be replaced in imagedefinitions.json
    essential = true,
    portMappings = [{
      containerPort = 5000,
      hostPort      = 5000
    }]
  }])
}

# ------------------------------------------
# ECS SERVICE
# ------------------------------------------

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
# IAM ROLE FOR CODEBUILD
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

# Attach permissions for ECR and CodeBuild actions
resource "aws_iam_role_policy_attachment" "codebuild_ecr_policy" {
  role       = aws_iam_role.codebuild_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "codebuild_basic_policy" {
  role       = aws_iam_role.codebuild_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess"
}

# Custom inline policy to allow CodeBuild to manage IAM roles
resource "aws_iam_role_policy" "codebuild_iam_access" {
  name = "AllowIAMRoleCreation"
  role = aws_iam_role.codebuild_service_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = [
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:AttachRolePolicy",
        "iam:PassRole"
      ],
      Resource = "*"
    }]
  })
}
