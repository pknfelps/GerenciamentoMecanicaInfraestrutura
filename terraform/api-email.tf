# A role da API pertence a base, nao ao bootstrap. Sem dependencia da stack email.
resource "aws_iam_role_policy" "api_email" {
  name = "invoke-email"
  role = aws_iam_role.api_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadEmailInvocationContract"
        Effect = "Allow"
        Action = ["ssm:GetParameters"]
        Resource = [for field in ["invocation-arn", "contract-version"] :
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/mecanica/${var.environment}/email/v1/${field}"
        ]
      },
      {
        Sid      = "InvokeEnvironmentEmailAlias"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${local.name_prefix}-email:live"
      }
    ]
  })
}
