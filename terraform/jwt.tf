# A chave e gerada apenas para uma nova versao; a revisao fixa evita rotacao por execucao.
resource "aws_secretsmanager_secret" "jwt" {
  name                    = "/mecanica/${var.environment}/base/jwt"
  description             = "Chave HS256 compartilhada entre API e autenticacao de ${var.environment}"
  recovery_window_in_days = 0
  tags                    = { Component = "base" }
}

ephemeral "random_password" "jwt" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id                = aws_secretsmanager_secret.jwt.id
  secret_string_wo         = jsonencode({ key = ephemeral.random_password.jwt.result })
  secret_string_wo_version = 1
}

resource "aws_iam_role" "api_runtime" {
  name        = "${local.name_prefix}-api-runtime"
  description = "Leitura JWT pelo runtime da API via EKS Pod Identity"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/eks-cluster-arn"            = aws_eks_cluster.main.arn
          "aws:RequestTag/kubernetes-namespace"       = "default"
          "aws:RequestTag/kubernetes-service-account" = "gerenciamento-api"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "api_jwt" {
  name = "read-jwt"
  role = aws_iam_role.api_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadEnvironmentJwt"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.jwt.arn
      },
      {
        Sid    = "ReadEnvironmentJwtConfiguration"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = [
          for field in ["jwt-secret-arn", "jwt-issuer", "jwt-audience"] :
          aws_ssm_parameter.configuration[field].arn
        ]
      }
    ]
  })
}

# O ServiceAccount sera aplicado pelo repositorio da API na integracao do runtime.
resource "aws_eks_pod_identity_association" "api" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "default"
  service_account = "gerenciamento-api"
  role_arn        = aws_iam_role.api_runtime.arn
  depends_on      = [aws_eks_addon.pod_identity_agent, aws_iam_role_policy.api_jwt]
}
