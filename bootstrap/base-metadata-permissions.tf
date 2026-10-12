# SG reservado da funcao e leitura regional de metadados de rede/SSM pelo Terraform da base.
resource "aws_iam_role_policy" "base_metadata_network" {
  for_each = local.environments
  name     = "base-metadata-network"
  role     = aws_iam_role.pipeline["${each.key}-base"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ReadRegionalMetadata"
        Effect    = "Allow"
        Action    = ["ec2:DescribeSecurityGroupRules", "ssm:DescribeParameters"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "CreateTaggedGroup"
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
        Condition = { StringEquals = {
          "aws:RequestTag/Project"     = var.project_name
          "aws:RequestTag/Environment" = each.key
          "aws:RequestTag/ManagedBy"   = "Terraform"
          "aws:RequestTag/Name"        = "${var.project_name}-${each.key}-auth"
        } }
      },
      {
        Sid      = "UseEnvironmentVpc"
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*"
        Condition = { StringEquals = {
          "ec2:ResourceTag/Project"     = var.project_name
          "ec2:ResourceTag/Environment" = each.key
          "ec2:ResourceTag/ManagedBy"   = "Terraform"
        } }
      },
      {
        Sid       = "TagGroupOnCreation"
        Effect    = "Allow"
        Action    = ["ec2:CreateTags"]
        Resource  = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
        Condition = { StringEquals = { "ec2:CreateAction" = "CreateSecurityGroup" } }
      },
      {
        Sid      = "ManageOwnReservedGroup"
        Effect   = "Allow"
        Action   = ["ec2:DeleteSecurityGroup", "ec2:RevokeSecurityGroupEgress"]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
        Condition = { StringEquals = {
          "ec2:ResourceTag/Project"     = var.project_name
          "ec2:ResourceTag/Environment" = each.key
          "ec2:ResourceTag/ManagedBy"   = "Terraform"
          "ec2:ResourceTag/Name"        = "${var.project_name}-${each.key}-auth"
        } }
      }
    ]
  })
}
