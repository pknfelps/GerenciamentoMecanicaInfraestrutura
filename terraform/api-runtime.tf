# ARNs previsiveis mantem a ordem base -> banco -> API sem ler SSM do banco na base.
resource "aws_iam_role_policy" "api_database" {
  name = "read-database"
  role = aws_iam_role.api_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadEnvironmentApiDatabaseSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:/mecanica/${var.environment}/database/api-??????"
      },
      {
        Sid    = "ReadEnvironmentApiDatabaseConfiguration"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = [
          for field in ["endpoint", "port", "database-name", "api-secret-arn", "api-db-user", "ssl-mode"] :
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/mecanica/${var.environment}/database/v2/${field}"
        ]
      }
    ]
  })
}
