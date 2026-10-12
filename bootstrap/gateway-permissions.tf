# REST children inherit the API tags for IAM authorization.
locals {
  gateway_policies = { for environment in local.environments : environment => {
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "GrantOnlyApiGatewayInvocation",
        "Effect" : "Allow",
        "Action" : [
          "lambda:AddPermission"
        ],
        "Resource" : "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-${environment}-auth:*",
        "Condition" : {
          "StringEquals" : {
            "lambda:Principal" : "apigateway.amazonaws.com"
          }
        }
      },
      {
        "Sid" : "CreateEnvironmentRestApi",
        "Effect" : "Allow",
        "Action" : [
          "apigateway:POST",
          "apigateway:PUT"
        ],
        "Resource" : "arn:aws:apigateway:${var.aws_region}::/restapis",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/Component" : "gateway",
            "apigateway:Request/ApiName" : "${var.project_name}-${environment}-gateway"
          }
        }
      },
      {
        "Sid" : "ManageEnvironmentRestApiAndChildren",
        "Effect" : "Allow",
        "Action" : [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:PUT",
          "apigateway:PATCH",
          "apigateway:DELETE"
        ],
        "Resource" : [
          "arn:aws:apigateway:${var.aws_region}::/restapis/*",
          "arn:aws:apigateway:${var.aws_region}::/tags/arn:aws:apigateway:${var.aws_region}::/restapis/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:ResourceTag/Project" : "${var.project_name}",
            "aws:ResourceTag/Environment" : "${environment}",
            "aws:ResourceTag/Component" : "gateway"
          }
        }
      },
      {
        "Sid" : "CreateEnvironmentVpcLink",
        "Effect" : "Allow",
        "Action" : [
          "apigateway:POST",
          "apigateway:PUT"
        ],
        "Resource" : "arn:aws:apigateway:${var.aws_region}::/vpclinks",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/Component" : "gateway"
          }
        }
      },
      {
        "Sid" : "ManageEnvironmentVpcLink",
        "Effect" : "Allow",
        "Action" : [
          "apigateway:GET",
          "apigateway:PATCH",
          "apigateway:DELETE",
          "apigateway:POST",
          "apigateway:PUT"
        ],
        "Resource" : [
          "arn:aws:apigateway:${var.aws_region}::/vpclinks/*",
          "arn:aws:apigateway:${var.aws_region}::/tags/arn:aws:apigateway:${var.aws_region}::/vpclinks/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:ResourceTag/Project" : "${var.project_name}",
            "aws:ResourceTag/Environment" : "${environment}",
            "aws:ResourceTag/Component" : "gateway"
          }
        }
      },
      {
        "Sid" : "InspectRegionalAccount",
        "Effect" : "Allow",
        "Action" : [
          "apigateway:GET"
        ],
        "Resource" : "arn:aws:apigateway:${var.aws_region}::/account"
      },
      {
        "Sid" : "InspectPrivateNetwork",
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeNetworkInterfaces",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:DescribeTags"
        ],
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestedRegion" : "${var.aws_region}"
          }
        }
      },
      {
        "Sid" : "ManageEnvironmentInvocationPermission",
        "Effect" : "Allow",
        "Action" : [

          "lambda:RemovePermission",
          "lambda:GetPolicy"
        ],
        "Resource" : "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-${environment}-auth:*"
      },
      {
        "Sid" : "ManageEnvironmentAccessLogGroup",
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:ListTagsForResource",
          "logs:TagResource",
          "logs:UntagResource"
        ],
        "Resource" : [
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/apigateway/${var.project_name}-${environment}-gateway",
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/apigateway/${var.project_name}-${environment}-gateway:*"
        ]
      },
      {
        "Sid" : "LocateRegionalLogGroups",
        "Effect" : "Allow",
        "Action" : [
          "logs:DescribeLogGroups"
        ],
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestedRegion" : "${var.aws_region}"
          }
        }
      }
    ]
  } }
}
resource "aws_iam_policy" "gateway" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-gateway"
  path     = "/${var.project_name}/pipelines/"
  policy   = jsonencode(local.gateway_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.gateway_policies[each.key])) <= 6144
      error_message = "A policy Gateway ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}
resource "aws_iam_role_policy_attachment" "gateway" {
  for_each   = local.environments
  role       = aws_iam_role.pipeline["${each.key}-gateway"].name
  policy_arn = aws_iam_policy.gateway[each.key].arn
}
