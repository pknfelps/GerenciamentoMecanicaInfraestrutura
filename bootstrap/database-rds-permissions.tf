# A role database administra apenas a instancia PostgreSQL, o subnet group e o
# security group do proprio ambiente. O RDS guarda a senha mestre no Secrets
# Manager; a pipeline pode preparar esse segredo, mas nao ler seu valor.
# A service-linked role ja foi criada pelo bootstrap com a descricao historica
# abaixo. Mantemos seus atributos para evitar a substituicao de um recurso
# compartilhado e protegido contra destroy.
resource "aws_iam_service_linked_role" "rds" {
  aws_service_name = "rds.amazonaws.com"
  description      = "Service-linked role do Aurora gerenciada pelo bootstrap"

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  database_rds_arns = {
    for environment in local.environments : environment => {
      instance = "arn:aws:rds:${var.aws_region}:${var.aws_account_id}:db:${var.project_name}-${environment}-postgres"
      subgrp   = "arn:aws:rds:${var.aws_region}:${var.aws_account_id}:subgrp:${var.project_name}-${environment}-database"
    }
  }
  database_rds_secret_arn = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:rds!db-*"
}

moved {
  from = aws_iam_role_policy.database_aurora_rds
  to   = aws_iam_role_policy.database_rds
}

moved {
  from = aws_iam_role_policy.database_aurora_network
  to   = aws_iam_role_policy.database_network
}

resource "aws_iam_role_policy" "database_rds" {
  for_each = local.environments
  name     = "database-rds"
  role     = aws_iam_role.pipeline["${each.key}-database"].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadRegionalRds"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances", "rds:DescribeDBSubnetGroups",
          "rds:DescribeDBEngineVersions", "rds:DescribeOrderableDBInstanceOptions"
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "CreateTaggedPostgres"
        Effect   = "Allow"
        Action   = ["rds:CreateDBInstance"]
        Resource = [local.database_rds_arns[each.key].instance]
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project"     = var.project_name
            "aws:RequestTag/Environment" = each.key
            "aws:RequestTag/ManagedBy"   = "Terraform"
            "aws:RequestedRegion"        = var.aws_region
          }
          Bool = {
            "rds:ManageMasterUserPassword" = "true"
            "rds:PubliclyAccessible"       = "false"
            "rds:StorageEncrypted"         = "true"
          }
        }
      },
      {
        Sid      = "UseOwnSubnetGroupForPostgres"
        Effect   = "Allow"
        Action   = ["rds:CreateDBInstance"]
        Resource = [local.database_rds_arns[each.key].subgrp]
        Condition = { StringEquals = {
          "aws:RequestedRegion" = var.aws_region
        } }
      },
      {
        Sid      = "CreateTaggedSubnetGroup"
        Effect   = "Allow"
        Action   = ["rds:CreateDBSubnetGroup"]
        Resource = [local.database_rds_arns[each.key].subgrp]
        Condition = { StringEquals = {
          "aws:RequestTag/Project"     = var.project_name
          "aws:RequestTag/Environment" = each.key
          "aws:RequestTag/ManagedBy"   = "Terraform"
          "aws:RequestedRegion"        = var.aws_region
        } }
      },
      {
        Sid      = "ManageOwnPostgres"
        Effect   = "Allow"
        Action   = ["rds:ModifyDBInstance", "rds:DeleteDBInstance", "rds:ModifyDBSubnetGroup", "rds:DeleteDBSubnetGroup", "rds:RemoveTagsFromResource"]
        Resource = values(local.database_rds_arns[each.key])
        Condition = { StringEquals = {
          "aws:ResourceTag/Project"     = var.project_name
          "aws:ResourceTag/Environment" = each.key
          "aws:ResourceTag/ManagedBy"   = "Terraform"
          "aws:RequestedRegion"         = var.aws_region
        } }
      },
      {
        Sid       = "TagReservedRds"
        Effect    = "Allow"
        Action    = ["rds:AddTagsToResource"]
        Resource  = values(local.database_rds_arns[each.key])
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid       = "ReadReservedRdsTags"
        Effect    = "Allow"
        Action    = ["rds:ListTagsForResource"]
        Resource  = values(local.database_rds_arns[each.key])
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "PrepareRdsManagedSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:CreateSecret", "secretsmanager:TagResource"]
        Resource = [local.database_rds_secret_arn]
        Condition = { StringEquals = {
          "aws:RequestedRegion" = var.aws_region
        } }
      },
      {
        Sid      = "DescribeSecretsManagerKey"
        Effect   = "Allow"
        Action   = ["kms:DescribeKey"]
        Resource = ["arn:aws:kms:${var.aws_region}:${var.aws_account_id}:key/*"]
        Condition = { StringEquals = {
          "aws:RequestedRegion" = var.aws_region
        } }
      }
    ]
  })
}

resource "aws_iam_role_policy" "database_network" {
  for_each = local.environments
  name     = "database-network"
  role     = aws_iam_role.pipeline["${each.key}-database"].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ReadSecurityGroupRules"
        Effect    = "Allow"
        Action    = ["ec2:DescribeNetworkInterfaces", "ec2:DescribeSecurityGroupRules"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "CreateTaggedPostgresGroup"
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
        Condition = { StringEquals = {
          "aws:RequestTag/Project"     = var.project_name
          "aws:RequestTag/Environment" = each.key
          "aws:RequestTag/ManagedBy"   = "Terraform"
          "aws:RequestTag/Name"        = "${var.project_name}-${each.key}-postgres"
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
        Sid      = "ManageOwnPostgresGroup"
        Effect   = "Allow"
        Action   = ["ec2:DeleteSecurityGroup", "ec2:RevokeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
        Condition = { StringEquals = {
          "ec2:ResourceTag/Project"     = var.project_name
          "ec2:ResourceTag/Environment" = each.key
          "ec2:ResourceTag/ManagedBy"   = "Terraform"
          "ec2:ResourceTag/Name"        = "${var.project_name}-${each.key}-postgres"
          "aws:RequestedRegion"         = var.aws_region
        } }
      },
      {
        Sid      = "AuthorizeTaggedPostgresRule"
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
