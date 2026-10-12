resource "aws_iam_role_policy" "base_gateway_network" {
  for_each = local.environments
  name     = "base-gateway-network"
  role     = aws_iam_role.pipeline["${each.key}-base"].id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "CreateReservedGatewayGroup",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateSecurityGroup"
        ],
        "Resource" : "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${each.key}",
            "aws:RequestTag/Name" : "${var.project_name}-${each.key}-gateway",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "ManageReservedGatewayGroup",
        "Effect" : "Allow",
        "Action" : [
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupEgress"
        ],
        "Resource" : "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*",
        "Condition" : {
          "StringEquals" : {
            "ec2:ResourceTag/Project" : "${var.project_name}",
            "ec2:ResourceTag/Environment" : "${each.key}",
            "ec2:ResourceTag/Name" : "${var.project_name}-${each.key}-gateway"
          }
        }
      },
      {
        "Sid" : "GatewayIngressOnEnvironmentNlb",
        "Effect" : "Allow",
        "Action" : [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ],
        "Resource" : "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*",
        "Condition" : {
          "StringEquals" : {
            "ec2:ResourceTag/Project" : "${var.project_name}",
            "ec2:ResourceTag/Environment" : "${each.key}",
            "ec2:ResourceTag/Name" : "${var.project_name}-${each.key}-nlb"
          }
        }
      },
      {
        "Sid" : "ManageTaggedGatewayEgressRule",
        "Effect" : "Allow",
        "Action" : [
          "ec2:ModifySecurityGroupRules",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ],
        "Resource" : "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group-rule/*",
        "Condition" : {
          "StringEquals" : {
            "aws:ResourceTag/Project" : "${var.project_name}",
            "aws:ResourceTag/Environment" : "${each.key}",
            "aws:ResourceTag/Component" : "gateway-network"
          }
        }
      },
      {
        "Sid" : "CreateTaggedGatewayEgressRule",
        "Effect" : "Allow",
        "Action" : [
          "ec2:AuthorizeSecurityGroupEgress"
        ],
        "Resource" : "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group-rule/*",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${each.key}",
            "aws:RequestTag/Component" : "gateway-network",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "TagNewGatewayEgressRule",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateTags"
        ],
        "Resource" : "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group-rule/*",
        "Condition" : {
          "StringEquals" : {
            "ec2:CreateAction" : "AuthorizeSecurityGroupEgress",
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${each.key}",
            "aws:RequestTag/Component" : "gateway-network"
          }
        }
      }
    ]
  })
}
