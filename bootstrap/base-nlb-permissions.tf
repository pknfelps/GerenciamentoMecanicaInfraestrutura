resource "aws_iam_role_policy" "base_nlb" {
  for_each = local.environments
  name     = "base-nlb"
  role     = aws_iam_role.pipeline["${each.key}-base"].id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ReadRegionalNlbAndAutoscaling",
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeLoadBalancerTargetGroups",
          "autoscaling:DescribeScalingActivities"
        ],
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestedRegion" : "${var.aws_region}"
          }
        }
      },
      {
        "Sid" : "CreateOwnNlbAndTargetGroup",
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup"
        ],
        "Resource" : [
          "arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:loadbalancer/net/${var.project_name}-${each.key}-api/*",
          "arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:targetgroup/${var.project_name}-${each.key}-api/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${each.key}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "ManageOwnNlbAndTargetGroup",
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup"
        ],
        "Resource" : [
          "arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:loadbalancer/net/${var.project_name}-${each.key}-api/*",
          "arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:targetgroup/${var.project_name}-${each.key}-api/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:ResourceTag/Project" : "${var.project_name}",
            "aws:ResourceTag/Environment" : "${each.key}"
          }
        }
      },
      {
        "Sid" : "ManageOwnListener",
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyListenerAttributes"
        ],
        "Resource" : [
          "arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:loadbalancer/net/${var.project_name}-${each.key}-api/*",
          "arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:listener/net/${var.project_name}-${each.key}-api/*/*"
        ]
      },
      {
        "Sid" : "TagOwnNlbResources",
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ],
        "Resource" : [
          "arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:loadbalancer/net/${var.project_name}-${each.key}-api/*",
          "arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:targetgroup/${var.project_name}-${each.key}-api/*",
          "arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:listener/net/${var.project_name}-${each.key}-api/*/*"
        ]
      },
      {
        "Sid" : "AttachOwnEksGroup",
        "Effect" : "Allow",
        "Action" : [
          "autoscaling:AttachLoadBalancerTargetGroups",
          "autoscaling:DetachLoadBalancerTargetGroups"
        ],
        "Resource" : "arn:aws:autoscaling:${var.aws_region}:${var.aws_account_id}:autoScalingGroup:*:autoScalingGroupName/eks-${var.project_name}-${each.key}-eks-nodes-*",
        "Condition" : {
          "StringEquals" : {
            "autoscaling:ResourceTag/eks:cluster-name" : "${var.project_name}-${each.key}-eks"
          }
        }
      },
      {
        "Sid" : "CreateElbServiceRole",
        "Effect" : "Allow",
        "Action" : [
          "iam:CreateServiceLinkedRole"
        ],
        "Resource" : "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/elasticloadbalancing.amazonaws.com/AWSServiceRoleForElasticLoadBalancing",
        "Condition" : {
          "StringEquals" : {
            "iam:AWSServiceName" : "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        "Sid" : "CreateNlbGroup",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateSecurityGroup"
        ],
        "Resource" : "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${each.key}",
            "aws:RequestTag/ManagedBy" : "Terraform",
            "aws:RequestTag/Name" : "${var.project_name}-${each.key}-nlb"
          }
        }
      },
      {
        "Sid" : "ManageNlbGroup",
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
            "ec2:ResourceTag/Name" : "${var.project_name}-${each.key}-nlb"
          }
        }
      },
      {
        "Sid" : "NlbIngressOnOwnEksGroup",
        "Effect" : "Allow",
        "Action" : [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ],
        "Resource" : "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*",
        "Condition" : {
          "StringEquals" : {
            "ec2:ResourceTag/aws:eks:cluster-name" : "${var.project_name}-${each.key}-eks"
          }
        }
      }
    ]
  })
}
