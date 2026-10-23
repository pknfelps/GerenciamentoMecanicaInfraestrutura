# Somente a descoberta do contrato e o alias estavel; sem SMTP/configuracao de transporte.
locals {
  email_consumer_fields = ["invocation-arn", "contract-version"]
  auth_email_policies = { for environment in local.environments : environment => {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadEmailInvocationContract"
        Effect   = "Allow"
        Action   = ["ssm:GetParameters"]
        Resource = [for field in local.email_consumer_fields : "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/${environment}/email/v1/${field}"]
      },
      {
        Sid      = "InvokeEnvironmentEmailAlias"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-${environment}-email:live"
      }
    ]
  } }
}

resource "aws_iam_policy" "auth_email" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-auth-email"
  path     = "/${var.project_name}/runtime/"
  policy   = jsonencode(local.auth_email_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.auth_email_policies[each.key])) <= 6144
      error_message = "A policy de consumo email ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "auth_email" {
  for_each   = local.environments
  role       = aws_iam_role.auth_runtime[each.key].name
  policy_arn = aws_iam_policy.auth_email[each.key].arn
}
