provider "aws" {
  region = "ap-south-1"
}

# Declare the input variable for image_tag
variable "image_tag" {
  description = "The image tag to be used for the Docker image"
  type        = string
}

# Declare the input variable for subnet_ids
variable "subnet_ids" {
  description = "List of subnet IDs for the ECS service"
  type        = list(string)
}

# Declare the input variable for security_group_id
variable "security_group_id" {
  description = "Security group ID to associate with ECS service"
  type        = string
}

# Declare the input variable for vpc_id
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

# Define the ECR repository
resource "aws_ecr_repository" "private_flask_repo" {
  name = "private-flask-repo"
}

# Define the ECS cluster
resource "aws_ecs_cluster" "project_cluster" {
  name = "project-cluster"
}

# Define IAM role for ECS task execution (this assumes the role doesn't exist)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect    = "Allow"
        Sid       = ""
      }
    ]
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Attach ECS task execution policy to IAM role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_execution_role.name
}

# Add IAM policy for ECR repository access
resource "aws_iam_role_policy_attachment" "ecs_task_ecr_access_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.ecs_task_execution_role.name
}

# Define the ECS task definition
resource "aws_ecs_task_definition" "task_definition" {
  family                   = "flask-task"
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([{
    name      = "my-container"
    image     = "${aws_ecr_repository.private_flask_repo.repository_url}:${var.image_tag}"
    cpu       = 256
    memory    = 512
    essential = true
  }])
}

# Define the ECS service
resource "aws_ecs_service" "service" {
  name            = "flask-service"
  cluster         = aws_ecs_cluster.project_cluster.id
  task_definition = aws_ecs_task_definition.task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups = [var.security_group_id]
    assign_public_ip = false
  }
}
