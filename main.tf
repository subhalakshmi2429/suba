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
    name      = "my-final-test-container",
    image     = "dummy", # Replaced by imagedefinitions.json in CodePipeline
    essential = true,
    portMappings = [{
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
      Effect   = "Allow",
      Action   = [
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
# IAM ROLE FOR CODEPIPELINE
# ----------------------------

resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "codepipeline.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipelineFullAccess"
}

# ----------------------------
# CODEBUILD PROJECT
# ----------------------------

resource "aws_codebuild_project" "backend_build" {
  name         = "backend-build"
  service_role = aws_iam_role.codebuild_service_role.arn

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
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

# ----------------------------
# CODEPIPELINE
# ----------------------------

resource "aws_codepipeline" "my_pipeline" {
  name     = "MyPipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = "codepipeline-ap-south-1-af974c323746-4351-944a-96ce98c44ece"  # Replace with your actual S3 bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source-output"]
      configuration = {
        ConnectionArn    = "arn:aws:codestar-connections:ap-south-1:123456789012:connection/abc123xyz456"  # Replace with your connection ARN
        FullRepositoryId = "subhalakshmi2429/suba"
        BranchName       = "master"
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAction"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source-output"]
      output_artifacts = ["build-output"]
      configuration = {
        ProjectName = aws_codebuild_project.backend_build.name
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
      version          = "1"
      input_artifacts  = ["build-output"]
      configuration = {
        ProjectName = aws_codebuild_project.backend_build.name
        Buildspec   = "buildspec-deploy.yml"
      }
    }
  }
}
