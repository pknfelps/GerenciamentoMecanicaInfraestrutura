# A role do banco gerencia somente o cluster, o writer, o subnet group e o SG
# reservados ao próprio ambiente. A senha administrativa continua sob o RDS;
# esta policy não permite ler valores no Secrets Manager nem passar IAM roles.
# O RDS precisa da service-linked role na primeira criação do cluster. O
# bootstrap compartilhado a cria, evitando iam:CreateServiceLinkedRole na pipeline.
resource "aws_iam_service_linked_role" "rds" {
  aws_service_name = "rds.amazonaws.com"
  description      = "Service-linked role do Aurora gerenciada pelo bootstrap"

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  database_aurora_arns = {
    for environment in local.environments : environment => {
      cluster = "arn:aws:rds:${var.aws_region}:${var.aws_account_id}:cluster:${var.project_name}-${environment}-aurora"
      writer  = "arn:aws:rds:${var.aws_region}:${var.aws_account_id}:db:${var.project_name}-${environment}-aurora-writer"
      subgrp  = "arn:aws:rds:${var.aws_region}:${var.aws_account_id}:subgrp:${var.project_name}-${environment}-database"
    }
  }
}

resource "aws_iam_role_policy" "database_aurora_rds" {
  for_each = local.environments
  name     = "database-aurora-rds"
  role     = aws_iam_role.pipeline["${each.key}-database"].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadRegionalAurora"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters", "rds:DescribeDBInstances",
          "rds:DescribeDBSubnetGroups", "rds:DescribeDBEngineVersions",
          "rds:DescribeOrderableDBInstanceOptions"
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "CreateTaggedAurora"
        Effect   = "Allow"
        Action   = ["rds:CreateDBCluster", "rds:CreateDBInstance", "rds:CreateDBSubnetGroup"]
        Resource = values(local.database_aurora_arns[each.key])
        Condition = { StringEquals = {
          "aws:RequestTag/Project"     = var.project_name
          "aws:RequestTag/Environment" = each.key
          "aws:RequestTag/ManagedBy"   = "Terraform"
          "aws:RequestedRegion"        = var.aws_region
        } }
      },
      {
        Sid      = "ManageOwnAurora"
        Effect   = "Allow"
        Action   = ["rds:ModifyDBCluster", "rds:ModifyDBInstance", "rds:ModifyDBSubnetGroup", "rds:DeleteDBCluster", "rds:DeleteDBInstance", "rds:DeleteDBSubnetGroup", "rds:RemoveTagsFromResource"]
        Resource = values(local.database_aurora_arns[each.key])
        Condition = { StringEquals = {
          "aws:ResourceTag/Project"     = var.project_name
          "aws:ResourceTag/Environment" = each.key
          "aws:ResourceTag/ManagedBy"   = "Terraform"
          "aws:RequestedRegion"         = var.aws_region
        } }
      },
      {
        Sid       = "TagReservedAurora"
        Effect    = "Allow"
        Action    = ["rds:AddTagsToResource"]
        Resource  = values(local.database_aurora_arns[each.key])
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid       = "ReadReservedAuroraTags"
        Effect    = "Allow"
        Action    = ["rds:ListTagsForResource"]
        Resource  = values(local.database_aurora_arns[each.key])
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      }
    ]
  })
}

resource "aws_iam_role_policy" "database_aurora_network" {
  for_each = local.environments
  name     = "database-aurora-network"
  role     = aws_iam_role.pipeline["${each.key}-database"].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ReadSecurityGroupRules"
        Effect    = "Allow"
        Action    = ["ec2:DescribeSecurityGroupRules"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "CreateTaggedAuroraGroup"
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
        Condition = { StringEquals = {
          "aws:RequestTag/Project"     = var.project_name
          "aws:RequestTag/Environment" = each.key
          "aws:RequestTag/ManagedBy"   = "Terraform"
          "aws:RequestTag/Name"        = "${var.project_name}-${each.key}-aurora"
          "aws:RequestedRegion"        = var.aws_region
        } }
      },
      {
        Sid      = "UseOwnEnvironmentVpc"
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*"
        Condition = { StringEquals = {
          "ec2:ResourceTag/Project"     = var.project_name
          "ec2:ResourceTag/Environment" = each.key
          "ec2:ResourceTag/ManagedBy"   = "Terraform"
          "aws:RequestedRegion"         = var.aws_region
        } }
      },
      {
        Sid      = "TagGroupAndRuleOnCreation"
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*", "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group-rule/*"]
        Condition = { StringEquals = {
          "ec2:CreateAction"    = ["CreateSecurityGroup", "AuthorizeSecurityGroupIngress"]
          "aws:RequestedRegion" = var.aws_region
        } }
      },
      {
        Sid      = "ManageOwnAuroraGroup"
        Effect   = "Allow"
        Action   = ["ec2:DeleteSecurityGroup", "ec2:RevokeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
        Condition = { StringEquals = {
          "ec2:ResourceTag/Project"     = var.project_name
          "ec2:ResourceTag/Environment" = each.key
          "ec2:ResourceTag/ManagedBy"   = "Terraform"
          "ec2:ResourceTag/Name"        = "${var.project_name}-${each.key}-aurora"
          "aws:RequestedRegion"         = var.aws_region
        } }
      },
      {
        Sid      = "AuthorizeTaggedAuroraRule"
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress"]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group-rule/*"
        Condition = { StringEquals = {
          "aws:RequestTag/Project"     = var.project_name
          "aws:RequestTag/Environment" = each.key
          "aws:RequestTag/ManagedBy"   = "Terraform"
          "aws:RequestedRegion"        = var.aws_region
        } }
      }
    ]
  })
}
