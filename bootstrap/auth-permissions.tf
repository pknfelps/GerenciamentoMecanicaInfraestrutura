# Policy gerenciada separada para a pipeline; ela nao administra a role persistente.
locals {
  auth_provision_policies = { for environment in local.environments : environment => {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageFunction"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction", "lambda:GetFunction", "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration", "lambda:DeleteFunction",
          "lambda:CreateAlias", "lambda:GetAlias", "lambda:UpdateAlias", "lambda:DeleteAlias", "lambda:ListAliases",
          "lambda:PublishVersion", "lambda:ListVersionsByFunction", "lambda:GetFunctionConcurrency",
          "lambda:PutFunctionConcurrency", "lambda:DeleteFunctionConcurrency", "lambda:InvokeFunction",
          "lambda:TagResource", "lambda:UntagResource", "lambda:ListTags",
          "lambda:GetFunctionCodeSigningConfig", "lambda:GetRuntimeManagementConfig", "lambda:GetFunctionRecursionConfig"
        ]
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-${environment}-auth",
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-${environment}-auth:*"
        ]
      },
      {
        Sid      = "ReadCollectorLayer"
        Effect   = "Allow"
        Action   = ["lambda:GetLayerVersion"]
        Resource = "arn:aws:lambda:us-east-1:184161586896:layer:opentelemetry-collector-amd64-0_22_0:1"
      },
      {
        Sid      = "ReadRuntimeRole"
        Effect   = "Allow"
        Action   = ["iam:GetRole"]
        Resource = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-auth-runtime"
      },
      {
        Sid       = "PassRuntimeRole"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-auth-runtime"
        Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } }
      },
      {
        Sid    = "ManageFunctionLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
          "logs:TagResource", "logs:UntagResource", "logs:ListTagsForResource",
          "logs:DescribeLogStreams", "logs:GetLogEvents", "logs:FilterLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${var.project_name}-${environment}-auth",
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${var.project_name}-${environment}-auth:*"
        ]
      },
      {
        Sid    = "ReadRegionalMetadata"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules", "ec2:DescribeNetworkInterfaces", "ec2:GetSecurityGroupsForVpc",
          "logs:DescribeLogGroups", "ssm:DescribeParameters", "lambda:GetAccountSettings"
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid    = "ReadArtifactVersions"
        Effect = "Allow"
        Action = ["s3:GetObjectVersion"]
        Resource = [
          "${local.bucket_arns.artifacts}/sam/auth/${environment}/*",
          "${local.bucket_arns.artifacts}/contracts/auth/*"
        ]
      },
      {
        Sid    = "ManageReservedGroupEgress"
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
          "ec2:ModifySecurityGroupRules", "ec2:UpdateSecurityGroupRuleDescriptionsEgress"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
        Condition = { StringEquals = {
          "ec2:ResourceTag/Project"     = var.project_name
          "ec2:ResourceTag/Environment" = environment
          "ec2:ResourceTag/ManagedBy"   = "Terraform"
          "ec2:ResourceTag/Name"        = "${var.project_name}-${environment}-auth"
        } }
      }
    ]
  } }
}

resource "aws_iam_policy" "auth_provision" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-auth-provision"
  path     = "/${var.project_name}/pipelines/"
  policy   = jsonencode(local.auth_provision_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.auth_provision_policies[each.key])) <= 6144
      error_message = "A policy gerenciada auth ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "auth_provision" {
  for_each   = local.environments
  role       = aws_iam_role.pipeline["${each.key}-auth"].name
  policy_arn = aws_iam_policy.auth_provision[each.key].arn
}
