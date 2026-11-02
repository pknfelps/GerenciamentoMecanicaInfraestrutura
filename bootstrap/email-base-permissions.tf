# A base criara a rede SMTP/acesso de inspecao depois; aqui somente sua autorizacao.
locals {
  base_email_policies = { for environment in local.environments : environment => {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CreateReservedEmailGroup"
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
        Condition = { StringEquals = {
          "aws:RequestTag/Project"     = var.project_name
          "aws:RequestTag/Environment" = environment
          "aws:RequestTag/ManagedBy"   = "Terraform"
          "aws:RequestTag/Name"        = "${var.project_name}-${environment}-email"
        } }
      },
      {
        Sid      = "ManageReservedEmailGroup"
        Effect   = "Allow"
        Action   = ["ec2:DeleteSecurityGroup", "ec2:RevokeSecurityGroupEgress"]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
        Condition = { StringEquals = {
          "ec2:ResourceTag/Project"     = var.project_name
          "ec2:ResourceTag/Environment" = environment
          "ec2:ResourceTag/ManagedBy"   = "Terraform"
          "ec2:ResourceTag/Name"        = "${var.project_name}-${environment}-email"
        } }
      },
      {
        Sid      = "CreateTaggedSmtpTargetGroup"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateTargetGroup"]
        Resource = "arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:targetgroup/${var.project_name}-${environment}-smtp/*"
        Condition = { StringEquals = {
          "aws:RequestTag/Project"     = var.project_name
          "aws:RequestTag/Environment" = environment
          "aws:RequestTag/ManagedBy"   = "Terraform"
        } }
      },
      {
        Sid    = "ManageSmtpTargetGroup"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyTargetGroup", "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"
        ]
        Resource = "arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:targetgroup/${var.project_name}-${environment}-smtp/*"
      },
      {
        Sid       = "InspectRegionalEmailCollection"
        Effect    = "Allow"
        Action    = ["lambda:ListFunctions"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "CreateEmailInspectionAccess"
        Effect   = "Allow"
        Action   = ["eks:CreateAccessEntry"]
        Resource = "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.project_name}-${environment}-eks"
        Condition = { StringEquals = {
          "eks:principalArn"    = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}/pipelines/${var.project_name}-${environment}-email-github"
          "eks:accessEntryType" = "STANDARD"
        } }
      },
      {
        Sid    = "ManageEmailInspectionAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeAccessEntry", "eks:UpdateAccessEntry", "eks:DeleteAccessEntry", "eks:ListAssociatedAccessPolicies",
          "eks:TagResource", "eks:UntagResource", "eks:ListTagsForResource"
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-email-github/*"
      },
      {
        Sid      = "AssociateEmailApiView"
        Effect   = "Allow"
        Action   = ["eks:AssociateAccessPolicy"]
        Resource = "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-email-github/*"
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
        Sid       = "DisassociateEmailApiView"
        Effect    = "Allow"
        Action    = ["eks:DisassociateAccessPolicy"]
        Resource  = "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-email-github/*"
        Condition = { StringEquals = { "eks:policyArn" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy" } }
      }
    ]
  } }
}

resource "aws_iam_policy" "base_email" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-base-email"
  path     = "/${var.project_name}/pipelines/"
  policy   = jsonencode(local.base_email_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.base_email_policies[each.key])) <= 6144
      error_message = "A policy da base para email ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "base_email" {
  for_each   = local.environments
  role       = aws_iam_role.pipeline["${each.key}-base"].name
  policy_arn = aws_iam_policy.base_email[each.key].arn
}
