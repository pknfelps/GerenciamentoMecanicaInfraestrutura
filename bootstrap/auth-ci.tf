# CI de PR/manual: somente leitura da versao fixa do pacote compartilhado.
resource "aws_iam_role" "auth_ci" {
  name = "${var.project_name}-auth-ci-github"
  path = "/${var.project_name}/pipelines/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.oidc_arn }
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = [
          "${var.github_subject_prefixes.auth}:pull_request",
          "${var.github_subject_prefixes.auth}:ref:refs/heads/develop",
          "${var.github_subject_prefixes.auth}:ref:refs/heads/main"
        ]
      } }
    }]
  })
  depends_on = [aws_iam_openid_connect_provider.github]
}

resource "aws_iam_role_policy" "auth_ci" {
  name = "ReadAuthContracts100"
  role = aws_iam_role.auth_ci.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "s3:GetObject"
      Resource = [
        "${local.bucket_arns.artifacts}/packages/GerenciamentoMecanica.Auth.Contracts/1.0.0/GerenciamentoMecanica.Auth.Contracts.1.0.0.nupkg",
        "${local.bucket_arns.artifacts}/packages/GerenciamentoMecanica.Auth.Contracts/1.0.0/GerenciamentoMecanica.Auth.Contracts.1.0.0.nupkg.sha256"
      ]
    }]
  })
}

output "auth_ci_role_arn" {
  description = "Variavel de repositorio AWS_CI_ROLE_ARN da autenticacao; nao usar Environment de deploy no CI."
  value       = aws_iam_role.auth_ci.arn
}
