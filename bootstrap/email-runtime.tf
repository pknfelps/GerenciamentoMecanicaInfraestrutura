# Identidade persistente; a futura stack SAM email somente referencia esta role.
locals {
  email_vpc_actions = [
    "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets",
    "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses"
  ]
  email_runtime_policies = { for environment in local.environments : environment => {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteEmailFunctionLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${var.project_name}-${environment}-email:*"
      },
      {
        Sid       = "ManageLambdaInterfaces"
        Effect    = "Allow"
        Action    = local.email_vpc_actions
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid       = "DenyInterfaceOperationsFromEmailCode"
        Effect    = "Deny"
        Action    = local.email_vpc_actions
        Resource  = "*"
        Condition = { ArnEquals = { "lambda:SourceFunctionArn" = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-${environment}-email" } }
      }
    ]
  } }
}

resource "aws_iam_role" "email_runtime" {
  for_each    = local.environments
  name        = "${var.project_name}-${each.key}-email-runtime"
  description = "Transporte SMTP privado; sem acesso a banco, JWT ou Secrets"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Environment = each.key, Component = "email" }
}

resource "aws_iam_role_policy" "email_runtime" {
  for_each = local.environments
  name     = "email-runtime-access"
  role     = aws_iam_role.email_runtime[each.key].id
  policy   = jsonencode(local.email_runtime_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.email_runtime_policies[each.key])) <= 10240
      error_message = "A policy inline email ultrapassa o limite IAM de 10240 caracteres."
    }
  }
}
