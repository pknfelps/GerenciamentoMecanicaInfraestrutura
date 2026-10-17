# Inspecao de consumidores antes de descartar recursos; sem leitura de Secrets/estados externos.
locals {
  destroy_inspection_policies = {
    for key, config in local.roles : key => {
      Version = "2012-10-17"
      Statement = concat(
        contains(["api", "auth"], config.component) ? [{
          Sid    = "InspectRegionalGatewayCollections"
          Effect = "Allow"
          Action = ["apigateway:GET"]
          Resource = [
            format("arn:aws:apigateway:%s::/restapis", var.aws_region),
            format("arn:aws:apigateway:%s::/vpclinks", var.aws_region),
          ]
          Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
        }] : [],
        config.component == "database" ? [{
          Sid       = "InspectRegionalConsumers"
          Effect    = "Allow"
          Action    = ["lambda:ListFunctions", "eks:ListClusters"]
          Resource  = "*"
          Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
        }] : [],
        config.component == "base" ? [{
          Sid       = "InspectRegionalDatabase"
          Effect    = "Allow"
          Action    = ["rds:DescribeDBInstances", "rds:DescribeDBSubnetGroups"]
          Resource  = "*"
          Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
        }] : [],
      )
    } if contains(["api", "auth", "database", "base"], config.component)
  }

  # Autorizacao administrativa separada das policies de inspecao.
  base_database_view_policies = {
    for environment in local.environments : environment => {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "AssociateDatabaseApiView"
          Effect   = "Allow"
          Action   = ["eks:AssociateAccessPolicy"]
          Resource = format("arn:aws:eks:%s:%s:access-entry/%s-%s-eks/role/%s/%s-%s-database-github/*", var.aws_region, var.aws_account_id, var.project_name, environment, var.aws_account_id, var.project_name, environment)
          Condition = {
            StringEquals = {
              "eks:policyArn"       = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
              "eks:accessScope"     = "namespace"
              "aws:RequestedRegion" = var.aws_region
            }
            "ForAllValues:StringEquals" = { "eks:namespaces" = ["default"] }
            Null                        = { "eks:namespaces" = "false" }
          }
        },
        {
          Sid      = "DisassociateDatabaseApiView"
          Effect   = "Allow"
          Action   = ["eks:DisassociateAccessPolicy"]
          Resource = format("arn:aws:eks:%s:%s:access-entry/%s-%s-eks/role/%s/%s-%s-database-github/*", var.aws_region, var.aws_account_id, var.project_name, environment, var.aws_account_id, var.project_name, environment)
          Condition = {
            StringEquals = {
              "eks:policyArn"       = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
              "aws:RequestedRegion" = var.aws_region
            }
          }
        },
      ]
    }
  }
}

resource "aws_iam_policy" "destroy_inspection" {
  for_each = local.destroy_inspection_policies
  name     = format("%s-%s-destroy-inspection", var.project_name, each.key)
  path     = format("/%s/pipelines/", var.project_name)
  policy   = jsonencode(each.value)

  lifecycle {
    precondition {
      condition     = length(jsonencode(each.value)) <= 6144
      error_message = "A policy de inspecao do destroy ultrapassa 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "destroy_inspection" {
  for_each   = local.destroy_inspection_policies
  role       = aws_iam_role.pipeline[each.key].name
  policy_arn = aws_iam_policy.destroy_inspection[each.key].arn
}

resource "aws_iam_policy" "base_database_view" {
  for_each = local.base_database_view_policies
  name     = format("%s-%s-base-database-view", var.project_name, each.key)
  path     = format("/%s/pipelines/", var.project_name)
  policy   = jsonencode(each.value)

  lifecycle {
    precondition {
      condition     = length(jsonencode(each.value)) <= 6144
      error_message = "A policy de leitura Kubernetes do banco ultrapassa 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "base_database_view" {
  for_each   = local.base_database_view_policies
  role       = aws_iam_role.pipeline[format("%s-base", each.key)].name
  policy_arn = aws_iam_policy.base_database_view[each.key].arn
}
