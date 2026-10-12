# Permissões operacionais da base; somente o bootstrap administrativo as altera.

locals {

  base_network_create_policies = { for environment in local.environments : environment => {
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ReadRegionalNetwork",
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcAttribute",
          "ec2:DescribeSubnets",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeRouteTables",
          "ec2:DescribeAddresses",
          "ec2:DescribeAddressesAttribute",
          "ec2:DescribeNatGateways",
          "ec2:DescribeVpcEndpoints",
          "ec2:DescribeVpcEndpointServices",
          "ec2:DescribePrefixLists",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeTags"
        ],
        "Resource" : [
          "*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestedRegion" : "${var.aws_region}"
          }
        }
      },
      {
        "Sid" : "CreateVpc",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateVpc"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "CreateInternetgateway",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateInternetGateway"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:internet-gateway/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "CreateSubnet",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateSubnet"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:subnet/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "CreateRoutetable",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateRouteTable"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:route-table/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "CreateElasticip",
        "Effect" : "Allow",
        "Action" : [
          "ec2:AllocateAddress"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:elastic-ip/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "CreateNatgateway",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateNatGateway"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:natgateway/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "CreateVpcendpoint",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateVpcEndpoint"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc-endpoint/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "UseVpc",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateSubnet",
          "ec2:CreateRouteTable",
          "ec2:CreateNatGateway",
          "ec2:CreateVpcEndpoint"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "ec2:ResourceTag/Project" : "${var.project_name}",
            "ec2:ResourceTag/Environment" : "${environment}",
            "ec2:ResourceTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "UseSubnet",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateNatGateway"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:subnet/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "ec2:ResourceTag/Project" : "${var.project_name}",
            "ec2:ResourceTag/Environment" : "${environment}",
            "ec2:ResourceTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "UseElasticip",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateNatGateway"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:elastic-ip/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "ec2:ResourceTag/Project" : "${var.project_name}",
            "ec2:ResourceTag/Environment" : "${environment}",
            "ec2:ResourceTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "UseRoutetable",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateVpcEndpoint"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:route-table/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "ec2:ResourceTag/Project" : "${var.project_name}",
            "ec2:ResourceTag/Environment" : "${environment}",
            "ec2:ResourceTag/ManagedBy" : "Terraform"
          }
        }
      }
    ]
  } }

  base_network_manage_policies = { for environment in local.environments : environment => {
    "Version" : "2012-10-17",
    "Statement" : [
      # O NAT já removeu a associação; aws_eip ainda chama o ID salvo no plano.
      # Exclui ambos os tipos reais suportados pela ação, permitindo somente a
      # chamada idempotente sem AllocationId/NetworkInterfaceID de recurso real.
      # Não usar Resource="*" nem condições de tags IfExists para essa chamada.
      {
        "Sid" : "DisassociateMissingAddress",
        "Effect" : "Allow",
        "Action" : [
          "ec2:DisassociateAddress"
        ],
        "NotResource" : [
          "arn:aws:ec2:*:*:elastic-ip/*",
          "arn:aws:ec2:*:*:network-interface/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestedRegion" : "${var.aws_region}"
          },
          "Null" : {
            "ec2:AllocationId" : "true",
            "ec2:NetworkInterfaceID" : "true"
          }
        }
      },
      {
        "Sid" : "ManageOwnNetwork",
        "Effect" : "Allow",
        "Action" : [
          "ec2:ModifyVpcAttribute",
          "ec2:ModifySubnetAttribute",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:CreateRoute",
          "ec2:ReplaceRoute",
          "ec2:DeleteRoute",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:ReplaceRouteTableAssociation",
          "ec2:ModifyVpcEndpoint",
          "ec2:DeleteVpcEndpoints",
          "ec2:DeleteNatGateway",
          "ec2:ReleaseAddress",
          "ec2:DeleteSubnet",
          "ec2:DeleteRouteTable",
          "ec2:DeleteInternetGateway",
          "ec2:DeleteVpc"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:internet-gateway/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:subnet/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:route-table/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:elastic-ip/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:natgateway/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc-endpoint/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "ec2:ResourceTag/Project" : "${var.project_name}",
            "ec2:ResourceTag/Environment" : "${environment}",
            "ec2:ResourceTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "TagOnCreation",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateTags"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:internet-gateway/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:subnet/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:route-table/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:elastic-ip/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:natgateway/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc-endpoint/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "ec2:CreateAction" : [
              "CreateVpc",
              "CreateInternetGateway",
              "CreateSubnet",
              "CreateRouteTable",
              "AllocateAddress",
              "CreateNatGateway",
              "CreateVpcEndpoint"
            ],
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "UpdateOwnTags",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateTags"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:internet-gateway/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:subnet/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:route-table/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:elastic-ip/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:natgateway/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc-endpoint/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "ec2:ResourceTag/Project" : "${var.project_name}",
            "ec2:ResourceTag/Environment" : "${environment}",
            "ec2:ResourceTag/ManagedBy" : "Terraform"
          },
          "StringEqualsIfExists" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "RemoveAdditionalTags",
        "Effect" : "Allow",
        "Action" : [
          "ec2:DeleteTags"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:internet-gateway/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:subnet/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:route-table/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:elastic-ip/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:natgateway/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc-endpoint/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "ec2:ResourceTag/Project" : "${var.project_name}",
            "ec2:ResourceTag/Environment" : "${environment}",
            "ec2:ResourceTag/ManagedBy" : "Terraform"
          },
          "ForAllValues:StringNotEquals" : {
            "aws:TagKeys" : [
              "Project",
              "Environment",
              "ManagedBy"
            ]
          },
          "Null" : {
            "aws:TagKeys" : "false"
          }
        }
      }
    ]
  } }

  base_eks_policies = { for environment in local.environments : environment => {
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ReadAddonCatalog",
        "Effect" : "Allow",
        "Action" : [
          "eks:DescribeAddonVersions"
        ],
        "Resource" : [
          "*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestedRegion" : "${var.aws_region}"
          }
        }
      },
      {
        "Sid" : "CreateTaggedCluster",
        "Effect" : "Allow",
        "Action" : [
          "eks:CreateCluster"
        ],
        "Resource" : [
          "*"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${environment}",
            "aws:RequestTag/ManagedBy" : "Terraform",
            "aws:RequestedRegion" : "${var.aws_region}",
            "eks:authenticationMode" : "API_AND_CONFIG_MAP"
          },
          "Bool" : {
            "eks:bootstrapClusterCreatorAdminPermissions" : "false"
          }
        }
      },
      {
        "Sid" : "ManageOwnCluster",
        "Effect" : "Allow",
        "Action" : [
          "eks:DescribeCluster",
          "eks:UpdateClusterConfig",
          "eks:UpdateClusterVersion",
          "eks:DeleteCluster",
          "eks:ListUpdates",
          "eks:DescribeUpdate",
          "eks:ListNodegroups",
          "eks:ListAddons",
          "eks:ListPodIdentityAssociations",
          "eks:ListAccessEntries",
          "eks:CreateNodegroup",
          "eks:CreateAddon",
        ],
        "Resource" : [
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.project_name}-${environment}-eks"
        ]
      },
      {
        "Sid" : "ManageOwnChildren",
        "Effect" : "Allow",
        "Action" : [
          "eks:DescribeNodegroup",
          "eks:UpdateNodegroupConfig",
          "eks:UpdateNodegroupVersion",
          "eks:DeleteNodegroup",
          "eks:DescribeAddon",
          "eks:UpdateAddon",
          "eks:DeleteAddon",
          "eks:DescribeUpdate",
          "eks:ListUpdates",
        ],
        "Resource" : [
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:nodegroup/${var.project_name}-${environment}-eks/${var.project_name}-${environment}-eks-nodes/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:addon/${var.project_name}-${environment}-eks/eks-pod-identity-agent/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:addon/${var.project_name}-${environment}-eks/metrics-server/*",

        ]
      },
      {
        "Sid" : "CreateKnownAccessEntries",
        "Effect" : "Allow",
        "Action" : [
          "eks:CreateAccessEntry"
        ],
        "Resource" : [
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.project_name}-${environment}-eks"
        ],
        "Condition" : {
          "StringEquals" : {
            "eks:principalArn" : [
              "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}/pipelines/${var.project_name}-${environment}-base-github",
              "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}/pipelines/${var.project_name}-${environment}-api-github",
              "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}/pipelines/${var.project_name}-${environment}-database-github",
              "arn:aws:iam::${var.aws_account_id}:user/mecanica"
            ],
            "eks:accessEntryType" : "STANDARD"
          }
        }
      },
      {
        "Sid" : "ManageKnownAccessEntries",
        "Effect" : "Allow",
        "Action" : [
          "eks:DescribeAccessEntry",
          "eks:UpdateAccessEntry",
          "eks:DeleteAccessEntry",
          "eks:ListAssociatedAccessPolicies"
        ],
        "Resource" : [
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-base-github/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-api-github/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-database-github/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/user/${var.aws_account_id}/mecanica/*"
        ]
      },
      {
        "Sid" : "AssociatePlatformAdmin",
        "Effect" : "Allow",
        "Action" : [
          "eks:AssociateAccessPolicy"
        ],
        "Resource" : [
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-base-github/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/user/${var.aws_account_id}/mecanica/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "eks:policyArn" : "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
            "eks:accessScope" : "cluster"
          }
        }
      },
      {
        "Sid" : "AssociateApiEdit",
        "Effect" : "Allow",
        "Action" : [
          "eks:AssociateAccessPolicy"
        ],
        "Resource" : [
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-api-github/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "eks:policyArn" : "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy",
            "eks:accessScope" : "namespace"
          },
          "ForAllValues:StringEquals" : {
            "eks:namespaces" : [
              "default"
            ]
          },
          "Null" : {
            "eks:namespaces" : "false"
          }
        }
      },
      {
        "Sid" : "AssociateDatabaseEdit",
        "Effect" : "Allow",
        "Action" : [
          "eks:AssociateAccessPolicy"
        ],
        "Resource" : [
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-database-github/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "eks:policyArn" : "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy",
            "eks:accessScope" : "namespace"
          },
          "ForAllValues:StringEquals" : {
            "eks:namespaces" : [
              "database-init"
            ]
          },
          "Null" : {
            "eks:namespaces" : "false"
          }
        }
      },
      {
        "Sid" : "DisassociateKnownPolicies",
        "Effect" : "Allow",
        "Action" : [
          "eks:DisassociateAccessPolicy"
        ],
        "Resource" : [
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-base-github/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-api-github/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-database-github/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/user/${var.aws_account_id}/mecanica/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "eks:policyArn" : [
              "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
              "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
            ]
          }
        }
      },
      {
        "Sid" : "TagOwnEks",
        "Effect" : "Allow",
        "Action" : [
          "eks:TagResource",
          "eks:UntagResource",
          "eks:ListTagsForResource"
        ],
        "Resource" : [
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.project_name}-${environment}-eks",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:nodegroup/${var.project_name}-${environment}-eks/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:addon/${var.project_name}-${environment}-eks/*",

          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-base-github/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-api-github/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/role/${var.aws_account_id}/${var.project_name}-${environment}-database-github/*",
          "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:access-entry/${var.project_name}-${environment}-eks/user/${var.aws_account_id}/mecanica/*"
        ]
      }
    ]
  } }

  base_iam_policies = { for environment in local.environments : environment => {
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ReadExecutionRoles",
        "Effect" : "Allow",
        "Action" : [
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:ListRoleTags"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-eks-cluster-role",
          "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-eks-node-role",
        ]
      },
      {
        "Sid" : "ManageExecutionRoles",
        "Effect" : "Allow",
        "Action" : [
          "iam:CreateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:DeleteRole",
          "iam:TagRole",
          "iam:UntagRole"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-eks-cluster-role",
          "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-eks-node-role",
        ]
      },
      {
        "Sid" : "AttachClusterPolicies",
        "Effect" : "Allow",
        "Action" : [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-eks-cluster-role"
        ],
        "Condition" : {
          "ArnEquals" : {
            "iam:PolicyARN" : [
              "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
            ]
          }
        }
      },
      {
        "Sid" : "AttachNodePolicies",
        "Effect" : "Allow",
        "Action" : [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-eks-node-role"
        ],
        "Condition" : {
          "ArnEquals" : {
            "iam:PolicyARN" : [
              "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
              "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
              "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
            ]
          }
        }
      },

      {
        "Sid" : "ReadOperator",
        "Effect" : "Allow",
        "Action" : [
          "iam:GetUser"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:user/mecanica"
        ]
      },
      {
        "Sid" : "PassClusterRole",
        "Effect" : "Allow",
        "Action" : [
          "iam:PassRole"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-eks-cluster-role"
        ],
        "Condition" : {
          "StringEquals" : {
            "iam:PassedToService" : "eks.amazonaws.com"
          }
        }
      },
      {
        "Sid" : "PassNodeRole",
        "Effect" : "Allow",
        "Action" : [
          "iam:PassRole"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-eks-node-role"
        ],
        "Condition" : {
          "StringEquals" : {
            "iam:PassedToService" : [
              "eks.amazonaws.com",
              "ec2.amazonaws.com"
            ]
          }
        }
      },

      {
        "Sid" : "ReadEksNodegroupServiceRole",
        "Effect" : "Allow",
        "Action" : [
          "iam:GetRole"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup"
        ]
      },
      {
        "Sid" : "CreateEksServiceRoles",
        "Effect" : "Allow",
        "Action" : [
          "iam:CreateServiceLinkedRole"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/eks.amazonaws.com/*",
          "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/*",
          "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/autoscaling.amazonaws.com/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "iam:AWSServiceName" : [
              "eks.amazonaws.com",
              "eks-nodegroup.amazonaws.com",
              "autoscaling.amazonaws.com"
            ]
          }
        }
      },
      {
        "Sid" : "InitializeEksServicePolicies",
        "Effect" : "Allow",
        "Action" : [
          "iam:PutRolePolicy"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/eks.amazonaws.com/*",
          "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/*",
          "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/autoscaling.amazonaws.com/*"
        ]
      }
    ]
  } }

}

resource "aws_iam_policy" "base_network_create" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-base-network_create"
  path     = "/${var.project_name}/pipelines/"
  policy   = jsonencode(local.base_network_create_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.base_network_create_policies[each.key])) <= 6144
      error_message = "A policy gerenciada ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "base_network_create" {
  for_each   = local.environments
  role       = aws_iam_role.pipeline["${each.key}-base"].name
  policy_arn = aws_iam_policy.base_network_create[each.key].arn
}

resource "aws_iam_policy" "base_network_manage" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-base-network_manage"
  path     = "/${var.project_name}/pipelines/"
  policy   = jsonencode(local.base_network_manage_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.base_network_manage_policies[each.key])) <= 6144
      error_message = "A policy gerenciada ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "base_network_manage" {
  for_each   = local.environments
  role       = aws_iam_role.pipeline["${each.key}-base"].name
  policy_arn = aws_iam_policy.base_network_manage[each.key].arn
}

resource "aws_iam_policy" "base_eks" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-base-eks"
  path     = "/${var.project_name}/pipelines/"
  policy   = jsonencode(local.base_eks_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.base_eks_policies[each.key])) <= 6144
      error_message = "A policy gerenciada ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "base_eks" {
  for_each   = local.environments
  role       = aws_iam_role.pipeline["${each.key}-base"].name
  policy_arn = aws_iam_policy.base_eks[each.key].arn
}

resource "aws_iam_policy" "base_iam" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-base-iam"
  path     = "/${var.project_name}/pipelines/"
  policy   = jsonencode(local.base_iam_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.base_iam_policies[each.key])) <= 6144
      error_message = "A policy gerenciada ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "base_iam" {
  for_each   = local.environments
  role       = aws_iam_role.pipeline["${each.key}-base"].name
  policy_arn = aws_iam_policy.base_iam[each.key].arn
}

# DescribeCluster é necessário para update-kubeconfig; autorização Kubernetes fica na base.
resource "aws_iam_role_policy" "workload_eks" {
  for_each = { for key, config in local.roles : key => config if contains(["api", "database"], config.component) }
  name     = "describe-own-cluster"
  role     = aws_iam_role.pipeline[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster"]
      Resource = ["arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.project_name}-${each.value.environment}-eks"]
    }]
  })
}
