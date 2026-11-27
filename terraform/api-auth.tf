resource "aws_iam_role_policy" "api_auth" {
  name = "invoke-auth"
  role = aws_iam_role.api_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeEnvironmentAuthAlias"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${local.name_prefix}-auth:live"
    }]
  })
}
