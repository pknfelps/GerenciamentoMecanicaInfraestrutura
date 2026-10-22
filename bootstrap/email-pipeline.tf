# Mesmo repositorio/Environment da autenticacao, com permissoes proprias por componente.
# Branches develop/hom e main/prd devem ser conferidas no Environment e workflow (AE.8).
resource "aws_iam_role" "email_pipeline" {
  for_each             = local.environments
  name                 = "${var.project_name}-${each.key}-email-github"
  path                 = "/${var.project_name}/pipelines/"
  description          = "GitHub Actions: email / ${each.key}"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "${var.github_subject_prefixes.auth}:environment:${each.key}"
      } }
    }]
  })
  tags       = { Environment = each.key, Component = "email" }
  depends_on = [aws_iam_openid_connect_provider.github]
}

locals {
  email_base_fields    = ["vpc-id", "workload-subnet-ids", "email-security-group-id", "nlb-security-group-id", "smtp-host", "smtp-port"]
  email_catalog_fields = ["function-name", "function-version", "invocation-arn", "contract-version", "zip-key"]
  email_pipeline_metadata_policies = { for environment in local.environments : environment => {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadEmailDeploymentMetadata"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:ListTagsForResource"]
        Resource = concat(
          [for field in local.email_base_fields : "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/${environment}/base/v2/${field}"],
          [for field in local.email_catalog_fields : "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/${environment}/email/v1/${field}"]
        )
      },
      {
        Sid      = "PublishOwnEmailCatalog"
        Effect   = "Allow"
        Action   = ["ssm:PutParameter", "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:DeleteParameter"]
        Resource = [for field in local.email_catalog_fields : "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/${environment}/email/v1/${field}"]
      }
    ]
  } }
}

resource "aws_iam_role_policy" "email_pipeline_metadata" {
  for_each = local.environments
  name     = "email-metadata-access"
  role     = aws_iam_role.email_pipeline[each.key].id
  policy   = jsonencode(local.email_pipeline_metadata_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.email_pipeline_metadata_policies[each.key])) <= 10240
      error_message = "A policy inline da pipeline email ultrapassa 10240 caracteres."
    }
  }
}

output "email_runtime_role_arns" {
  description = "Roles persistentes referenciadas pelo futuro template email, sem gerencia IAM pelo SAM."
  value       = { for environment, role in aws_iam_role.email_runtime : environment => role.arn }
}

output "email_github_environment_variables" {
  description = "Variaveis a cadastrar nos Environments hom/prd do Serverless depois do apply aprovado; nao configurar CI com esta role."
  value = { for environment, role in aws_iam_role.email_pipeline : environment => {
    AWS_EMAIL_ROLE_ARN = role.arn
    AWS_REGION         = var.aws_region
    ARTIFACTS_BUCKET   = local.buckets.artifacts
  } }
}
