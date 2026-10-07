# The runner reads only the RDS-managed master secret tagged by RDS with its
# environment's exact DB instance ARN. The secret name is random and changes
# when the database is recreated; the workflow also checks the ARN with RDS.
resource "aws_iam_role_policy" "database_init_secret_read" {
  for_each = local.environments
  name     = "database-init-secret-read"
  role     = aws_iam_role.pipeline["${each.key}-database"].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadRdsManagedMasterSecretForInit"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = local.database_rds_secret_arn
      Condition = { StringEquals = {
        "aws:RequestedRegion"                              = var.aws_region
        "aws:ResourceTag/aws:rds:primaryDBInstanceArn"     = local.database_rds_arns[each.key].instance
        "aws:ResourceTag/aws:secretsmanager:owningService" = "rds"
      } }
    }]
  })
}
