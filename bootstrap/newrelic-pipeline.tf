# Esta identidade acessa somente o backend persistente dos dashboards.
# A main e imposta pelo Environment newrelic e pelas checagens do workflow.
resource "aws_iam_role" "newrelic_pipeline" {
  name                 = "${var.project_name}-newrelic-github"
  path                 = "/${var.project_name}/pipelines/"
  description          = "GitHub Actions: estado persistente dos dashboards New Relic"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubNewRelicEnvironment"
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.oidc_arn }
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "${var.github_subject_prefixes.infra}:environment:newrelic"
      } }
    }]
  })
  tags = { Environment = "shared", Component = "observability" }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [aws_iam_openid_connect_provider.github]
}

resource "aws_iam_role_policy" "newrelic_pipeline" {
  name = "newrelic-state-access"
  role = aws_iam_role.newrelic_pipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "LocateStateBucket"
      Effect   = "Allow"
      Action   = ["s3:GetBucketLocation"]
      Resource = local.bucket_arns.state
      }, {
      Sid      = "ListDashboardState"
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = local.bucket_arns.state
      Condition = { StringEquals = { "s3:prefix" = [
        "shared/newrelic/terraform.tfstate",
        "shared/newrelic/terraform.tfstate.tflock",
        "shared/newrelic/workspaces/"
      ] } }
      }, {
      Sid      = "ReadWriteDashboardState"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "${local.bucket_arns.state}/shared/newrelic/terraform.tfstate"
      }, {
      Sid      = "ManageDashboardStateLock"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = "${local.bucket_arns.state}/shared/newrelic/terraform.tfstate.tflock"
    }]
  })
}

output "newrelic_pipeline_role_arn" {
  description = "Variavel AWS_NEW_RELIC_ROLE_ARN do Environment newrelic; acesso somente ao backend dos dashboards."
  value       = aws_iam_role.newrelic_pipeline.arn
}
