provider "aws" {
  region = "ap-south-1"
}

# ----------------------------
# DATA SOURCES
# ----------------------------

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

data "aws_ecr_repository" "private_repo" {
  name = "private-flask-repo"
}

data "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"
}

# ----------------------------
# ECS CLUSTER
# ----------------------------

resource "aws_ecs_cluster" "private_cluster" {
  name = "private-test-cluster"
}

# ----------------------------
# ECS TASK DEFINITION
# ----------------------------

resource "aws_ecs_task_definition" "private_task" {
  family                   = "private-test-task"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name  = "my-final-test-container",
    image = "dummy", # Replaced by imagedefinitions.json in CodePipeline
    essential = true,
    portMappings = [ {
      containerPort = 5000,
      hostPort      = 5000
    }]
  }])
}

# ----------------------------
# ECS SERVICE
# ----------------------------

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

# ----------------------------
# IAM ROLE FOR CODEBUILD
# ----------------------------

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

resource "aws_iam_role_policy" "codebuild_iam_access" {
  name = "AllowIAMRoleCreation"
  role = aws_iam_role.codebuild_service_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "iam:GetRole",
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:AttachRolePolicy",
        "iam:PassRole"
      ],
      Resource = "*"
    }]
  })
}

# ----------------------------
# CODEBUILD PROJECT
# ----------------------------

resource "aws_codebuild_project" "backend_build" {
  name          = "backend-build"
  service_role  = aws_iam_role.codebuild_service_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }

  source {
    type      = "GITHUB"
    location  = "https://github.com/subhalakshmi2429/suba.git"  # GitHub repository URL
    buildspec = "buildspec.yml"  # This buildspec is used for the Build stage
  }
}

# ----------------------------
# CODEPIPELINE
# ----------------------------

resource "aws_codepipeline" "my_pipeline" {
  name = "MyPipeline"

  artifact_store {
    location = "codepipeline-ap-south-1-af974c323746-4351-944a-96ce98c44ece"  # Replace with your actual S3 bucket name
    type     = "S3"
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAction"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source-output"]
      output_artifacts = ["build-output"]
      configuration = {
        ProjectName = "backend-build"  # This is your existing CodeBuild project for building the app
        Buildspec   = "buildspec.yml"  # This is the buildspec for the Build stage
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name             = "DeployAction"
      category         = "Deploy"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["build-output"]
      configuration = {
        ProjectName = "ECS-project"  # Replace with your actual ECS CodeBuild project for deployment
        Buildspec   = "buildspec-deploy.yml"  # Override with the deploy-specific buildspec file
      }
    }
  }
}
