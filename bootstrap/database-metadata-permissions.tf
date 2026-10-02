# Queries used by the database-release consumer. EC2 Describe APIs below do not
# support resource-level permissions; environment ownership is checked by the consumer.
resource "aws_iam_role_policy" "database_metadata_read" {
  for_each = local.environments
  name     = "database-metadata-read"
  role     = aws_iam_role.pipeline["${each.key}-database"].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "VerifyBaseNetwork"
      Effect = "Allow"
      Action = [
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups"
      ]
      Resource  = "*"
      Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
    }]
  })
}
