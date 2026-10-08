resource "aws_iam_role_policy" "database_auth_secret" {
  for_each = local.environments
  name     = "database-auth-secret"
  role     = aws_iam_role.pipeline["${each.key}-database"].name
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "CreateOwnCredential",
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:CreateSecret"
        ],
        "Resource" : "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${each.key}/database/auth-??????",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${each.key}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "TagNewCredential",
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:TagResource"
        ],
        "Resource" : "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${each.key}/database/auth-??????",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestTag/Project" : "${var.project_name}",
            "aws:RequestTag/Environment" : "${each.key}",
            "aws:RequestTag/ManagedBy" : "Terraform"
          }
        }
      },
      {
        "Sid" : "ReadOwnCredentialMetadata",
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:ListSecretVersionIds"
        ],
        "Resource" : "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${each.key}/database/auth-??????",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestedRegion" : "${var.aws_region}"
          }
        }
      },
      {
        "Sid" : "ManageOwnCredential",
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:DeleteSecret",
          "secretsmanager:RestoreSecret",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource"
        ],
        "Resource" : "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/mecanica/${each.key}/database/auth-??????",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestedRegion" : "${var.aws_region}",
            "aws:ResourceTag/Project" : "${var.project_name}",
            "aws:ResourceTag/Environment" : "${each.key}",
            "aws:ResourceTag/ManagedBy" : [
              "Terraform",
              "database-provision"
            ]
          }
        }
      }
    ]
  })
}
