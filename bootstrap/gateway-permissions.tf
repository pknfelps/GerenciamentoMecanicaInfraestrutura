# REST children inherit the API tags for IAM authorization.
locals {
  gateway_metadata_read_fields = {
    base = [
      "vpc-id", "workload-subnet-ids", "gateway-security-group-id",
      "nlb-arn", "nlb-security-group-id", "nlb-listener-port", "nlb-listener-protocol", "api-integration-uri"
    ]
    auth = ["function-name", "function-version", "invocation-arn", "openapi-key", "auth-contracts-version"]
    gateway = [
      "rest-api-id", "vpc-link-id", "stage-name", "endpoint",
      "api-openapi-key", "auth-openapi-key", "auth-invocation-arn"
    ]
  }
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
        "Action" : "apigateway:*",
        "Resource" : "arn:aws:apigateway:${var.aws_region}::/restapis",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/Component" : "gateway",
            "aws:RequestTag/ManagedBy" : "Terraform",
            "apigateway:Request/ApiName" : "${var.project_name}-${environment}-gateway"
          }
        }
      },
      {
        "Sid" : "CreateEnvironmentVpcLink",
        "Effect" : "Allow",
        # VPC Link V2 authorizes TagResource on this collection during creation.
        # The service registry declares it, although the IAM action catalog omits it.
        "Action" : "apigateway:*",
        "Resource" : "arn:aws:apigateway:${var.aws_region}::/vpclinks",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/Component" : "gateway",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "ReadRegionalRestApiMetadata",
        "Effect" : "Allow",
        "Action" : "apigateway:GET",
        # Deleted APIs have no tags. An unconditional read lets Terraform receive
        # NotFound and reconcile partial deletion; writes still require environment tags.
        "Resource" : "arn:aws:apigateway:${var.aws_region}::/restapis/*"
      },
      {
        "Sid" : "ReadRegionalVpcLinkMetadata",
        "Effect" : "Allow",
        # Deletion removes resource tags before the final GetVpcLink/NotFound.
        # Terraform must be able to wait and refresh without those tags.
        "Action" : "apigateway:GET",
        "Resource" : "arn:aws:apigateway:${var.aws_region}::/vpclinks/*"
      },
      {
        "Sid" : "ManageEnvironmentGatewayResources",
        "Effect" : "Allow",
        "Action" : "apigateway:*",
        "Resource" : [
          "arn:aws:apigateway:${var.aws_region}::/restapis/*",
          "arn:aws:apigateway:${var.aws_region}::/vpclinks/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:ResourceTag/Project" : "${var.project_name}",
            "aws:ResourceTag/Environment" : "${environment}",
            "aws:ResourceTag/Component" : "gateway",
            "aws:ResourceTag/ManagedBy" : "Terraform"
          },
          "StringEqualsIfExists" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/Component" : "gateway",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "AccessGatewayTagEndpoints",
        "Effect" : "Allow",
        # Tag endpoints do not expose aws:ResourceTag. AWS also checks GET/PATCH
        # or V2 tagging permissions on the target resource, authorized above.
        "Action" : ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:DELETE"],
        "Resource" : [
          "arn:aws:apigateway:${var.aws_region}::/tags/arn:aws:apigateway:${var.aws_region}::/restapis/*",
          "arn:aws:apigateway:${var.aws_region}::/tags/arn:aws:apigateway:${var.aws_region}::/vpclinks/*",
          "arn:aws:apigateway:${var.aws_region}::/tags/arn:aws:apigateway:${var.aws_region}::/v2/vpclinks/*",
          "arn:aws:apigateway:${var.aws_region}::/tags/${urlencode("arn:aws:apigateway:${var.aws_region}::/restapis/")}*",
          "arn:aws:apigateway:${var.aws_region}::/tags/${urlencode("arn:aws:apigateway:${var.aws_region}::/vpclinks/")}*",
          "arn:aws:apigateway:${var.aws_region}::/tags/${urlencode("arn:aws:apigateway:${var.aws_region}::/v2/vpclinks/")}*"
        ],
        "Condition" : {
          "StringEqualsIfExists" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/Component" : "gateway",
            "aws:RequestTag/ManagedBy" : "Terraform"
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
        "Sid" : "ReadRegionalParameterMetadata",
        "Effect" : "Allow",
        # DescribeParameters has no resource-level scope and returns metadata only.
        "Action" : "ssm:DescribeParameters",
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestedRegion" : "${var.aws_region}"
          }
        }
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
