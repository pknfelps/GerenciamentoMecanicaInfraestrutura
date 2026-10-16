# O bootstrap administra somente os metadados. O mantenedor cadastra o valor no console.
resource "aws_secretsmanager_secret" "newrelic" {
  for_each                = local.environments
  name                    = "/mecanica/${each.key}/observability/newrelic-license-key"
  description             = "License Key New Relic US; valor cadastrado manualmente, fora do Terraform"
  recovery_window_in_days = 7
  tags                    = { Environment = each.key, Component = "observability" }
  lifecycle {
    prevent_destroy = true
  }
}

locals {
  base_collector_policies = { for environment in local.environments : environment => {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InspectNewRelicCredential"
        Effect   = "Allow"
        Action   = ["secretsmanager:DescribeSecret", "secretsmanager:ListSecretVersionIds"]
        Resource = aws_secretsmanager_secret.newrelic[environment].arn
      },
      {
        Sid    = "ManageCollectorRuntimeRole"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:GetRole", "iam:UpdateRole", "iam:UpdateRoleDescription", "iam:UpdateAssumeRolePolicy", "iam:DeleteRole",
          "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole", "iam:GetRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy"
        ]
        Resource = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-collector-runtime"
      },
      {
        Sid       = "PassCollectorRuntimeRole"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-collector-runtime"
        Condition = { StringEquals = { "iam:PassedToService" = "pods.eks.amazonaws.com" } }
      }
    ]
  } }
}

resource "aws_iam_policy" "base_collector" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-base-collector"
  path     = "/${var.project_name}/pipelines/"
  policy   = jsonencode(local.base_collector_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.base_collector_policies[each.key])) <= 6144
      error_message = "A policy do Collector ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "base_collector" {
  for_each   = local.environments
  role       = aws_iam_role.pipeline["${each.key}-base"].name
  policy_arn = aws_iam_policy.base_collector[each.key].arn
}

output "newrelic_secret_arns" {
  description = "Metadados persistentes; cadastrar a License Key como texto simples no console AWS."
  value       = { for environment, secret in aws_secretsmanager_secret.newrelic : environment => secret.arn }
}
