# The database pipeline owns only the API credential for its own environment.
# Passwords are generated on the runner and never enter Terraform state.
resource "aws_iam_role_policy" "database_api_secret" {
  for_each = local.environments
  name     = "database-api-secret"
  role     = aws_iam_role.pipeline["${each.key}-database"].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CreateOwnApiCredential"
        Effect   = "Allow"
        Action   = ["secretsmanager:CreateSecret", "secretsmanager:TagResource"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${each.key}/database/api-??????"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion"        = var.aws_region
            "aws:RequestTag/Project"     = var.project_name
            "aws:RequestTag/Environment" = each.key
            "aws:RequestTag/ManagedBy"   = "database-provision"
          }
        }
      },
      {
        Sid      = "DescribeOwnApiCredential"
        Effect   = "Allow"
        Action   = ["secretsmanager:DescribeSecret"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${each.key}/database/api-??????"
        Condition = { StringEquals = {
          "aws:RequestedRegion" = var.aws_region
        } }
      },
      {
        Sid      = "ReadOwnApiCredential"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${each.key}/database/api-??????"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion"         = var.aws_region
            "aws:ResourceTag/Project"     = var.project_name
            "aws:ResourceTag/Environment" = each.key
            "aws:ResourceTag/ManagedBy"   = "database-provision"
          }
        }
      }
    ]
  })
}
