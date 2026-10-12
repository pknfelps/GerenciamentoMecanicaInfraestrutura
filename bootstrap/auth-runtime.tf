# Role e policy persistem no bootstrap apos o descarte do estado auth.
locals {
  auth_runtime_parameters = [
    "base/v2/jwt-secret-arn", "base/v2/jwt-issuer", "base/v2/jwt-audience",
    "database/v2/endpoint", "database/v2/port", "database/v2/database-name",
    "database/v2/auth-secret-arn", "database/v2/auth-db-user", "database/v2/ssl-mode"
  ]
  auth_eni_actions = [
    "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets",
    "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses"
  ]
  auth_runtime_policies = { for environment in local.environments : environment => {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadRuntimeParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameters"]
        Resource = [for field in local.auth_runtime_parameters : "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/mecanica/${environment}/${field}"]
      },
      {
        Sid    = "ReadCurrentRuntimeSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${environment}/base/jwt-??????",
          "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${environment}/database/auth-??????"
        ]
        Condition = { StringEquals = { "secretsmanager:VersionStage" = "AWSCURRENT" } }
      },
      {
        Sid      = "WriteFunctionLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${var.project_name}-${environment}-auth:*"
      },
      {
        Sid       = "ManageLambdaInterfaces"
        Effect    = "Allow"
        Action    = local.auth_eni_actions
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid       = "DenyInterfaceOperationsFromFunctionCode"
        Effect    = "Deny"
        Action    = local.auth_eni_actions
        Resource  = "*"
        Condition = { ArnEquals = { "lambda:SourceFunctionArn" = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-${environment}-auth" } }
      }
    ]
  } }
}

resource "aws_iam_role" "auth_runtime" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-auth-runtime"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Environment = each.key, Component = "auth" }
}

resource "aws_iam_role_policy" "auth_runtime" {
  for_each = local.environments
  name     = "auth-runtime-access"
  role     = aws_iam_role.auth_runtime[each.key].id
  policy   = jsonencode(local.auth_runtime_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.auth_runtime_policies[each.key])) <= 10240
      error_message = "A policy inline do runtime auth ultrapassa o limite IAM de 10240 caracteres."
    }
  }
}