# Policy gerenciada separada para a pipeline; ela nao administra a role persistente.
locals {
  email_provision_policies = { for environment in local.environments : environment => {
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
          "lambda:TagResource", "lambda:UntagResource", "lambda:ListTags",
          "lambda:GetFunctionCodeSigningConfig", "lambda:GetRuntimeManagementConfig", "lambda:GetFunctionRecursionConfig"
        ]
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-${environment}-email",
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-${environment}-email:*"
        ]
      },
      {
        Sid      = "ReadRuntimeRole"
        Effect   = "Allow"
        Action   = ["iam:GetRole"]
        Resource = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-email-runtime"
      },
      {
        Sid       = "PassRuntimeRole"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-email-runtime"
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
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${var.project_name}-${environment}-email",
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${var.project_name}-${environment}-email:*"
        ]
      },
      {
        Sid    = "ReadRegionalMetadata"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules", "ec2:DescribeNetworkInterfaces", "ec2:GetSecurityGroupsForVpc",
          "logs:DescribeLogGroups", "lambda:ListFunctions", "eks:ListClusters"
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "InspectApiClusterForEmailDestroy"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.project_name}-${environment}-eks"
      },
      {
        Sid    = "ManageReservedGroupEgress"
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
        Condition = { StringEquals = {
          "ec2:ResourceTag/Project"     = var.project_name
          "ec2:ResourceTag/Environment" = environment
          "ec2:ResourceTag/ManagedBy"   = "Terraform"
          "ec2:ResourceTag/Name"        = "${var.project_name}-${environment}-email"
        } }
      }
    ]
  } }
}

resource "aws_iam_policy" "email_provision" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-email-provision"
  path     = "/${var.project_name}/pipelines/"
  policy   = jsonencode(local.email_provision_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.email_provision_policies[each.key])) <= 6144
      error_message = "A policy gerenciada email ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "email_provision" {
  for_each   = local.environments
  role       = aws_iam_role.email_pipeline[each.key].name
  policy_arn = aws_iam_policy.email_provision[each.key].arn
}
