# Policy gerenciada separada: nao aumenta as policies inline da role da base.
locals {
  base_jwt_policies = { for environment in local.environments : environment => {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CreateEnvironmentJwtSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:CreateSecret", "secretsmanager:TagResource"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${environment}/base/jwt-??????"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project"     = var.project_name
            "aws:RequestTag/Environment" = environment
            "aws:RequestTag/ManagedBy"   = "Terraform"
          }
        }
      },
      {
        Sid      = "ReadEnvironmentJwtMetadata"
        Effect   = "Allow"
        Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetResourcePolicy", "secretsmanager:ListSecretVersionIds"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${environment}/base/jwt-??????"
      },
      {
        Sid    = "ManageEnvironmentJwtSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret", "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:DeleteSecret", "secretsmanager:RestoreSecret", "secretsmanager:TagResource", "secretsmanager:UntagResource"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${environment}/base/jwt-??????"
      },
      {
        Sid    = "ManageApiRuntimeRole"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:GetRole", "iam:UpdateRole", "iam:UpdateRoleDescription", "iam:UpdateAssumeRolePolicy", "iam:DeleteRole",
          "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole", "iam:GetRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy"
        ]
        Resource = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-api-runtime"
      },
      {
        Sid       = "PassApiRuntimeRole"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-api-runtime"
        Condition = { StringEquals = { "iam:PassedToService" = "pods.eks.amazonaws.com" } }
      },
      {
        Sid      = "CreateApiPodIdentity"
        Effect   = "Allow"
        Action   = ["eks:CreatePodIdentityAssociation", "eks:TagResource"]
        Resource = "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.project_name}-${environment}-eks"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project"     = var.project_name
            "aws:RequestTag/Environment" = environment
            "aws:RequestTag/ManagedBy"   = "Terraform"
          }
        }
      },
      {
        Sid    = "ManageEnvironmentPodIdentity"
        Effect = "Allow"
        Action = [
          "eks:DescribePodIdentityAssociation", "eks:UpdatePodIdentityAssociation", "eks:DeletePodIdentityAssociation",
          "eks:ListTagsForResource", "eks:TagResource", "eks:UntagResource"
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:podidentityassociation/${var.project_name}-${environment}-eks/*"
      }
    ]
  } }
}

resource "aws_iam_policy" "base_jwt" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-base-jwt"
  path     = "/${var.project_name}/pipelines/"
  policy   = jsonencode(local.base_jwt_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.base_jwt_policies[each.key])) <= 6144
      error_message = "A policy gerenciada JWT ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "base_jwt" {
  for_each   = local.environments
  role       = aws_iam_role.pipeline["${each.key}-base"].name
  policy_arn = aws_iam_policy.base_jwt[each.key].arn
}
