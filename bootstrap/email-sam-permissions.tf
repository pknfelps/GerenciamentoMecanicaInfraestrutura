# SAM usa as permissoes do chamador; nao cria uma role de execucao da stack.
locals {
  email_sam_policies = { for environment in local.environments : environment => {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageEnvironmentStack"
        Effect = "Allow"
        Action = [
          "cloudformation:CreateChangeSet", "cloudformation:DescribeChangeSet",
          "cloudformation:ExecuteChangeSet", "cloudformation:DeleteChangeSet",
          "cloudformation:DeleteStack", "cloudformation:DescribeStacks",
          "cloudformation:DescribeStackResources", "cloudformation:ListStackResources",
          "cloudformation:DescribeStackEvents", "cloudformation:GetTemplate",
          "cloudformation:GetTemplateSummary", "cloudformation:ListChangeSets"
        ]
        Resource = "arn:aws:cloudformation:${var.aws_region}:${var.aws_account_id}:stack/${var.project_name}-${environment}-email/*"
      },
      {
        Sid      = "InspectSamCompanionStack"
        Effect   = "Allow"
        Action   = ["cloudformation:DescribeStacks"]
        Resource = "arn:aws:cloudformation:${var.aws_region}:${var.aws_account_id}:stack/${var.project_name}-${environment}-email-${substr(md5("${var.project_name}-${environment}-email"), 0, 8)}-CompanionStack/*"
      },
      {
        Sid    = "UseApprovedTransforms"
        Effect = "Allow"
        Action = ["cloudformation:CreateChangeSet"]
        Resource = [
          "arn:aws:cloudformation:${var.aws_region}:aws:transform/Serverless-2016-10-31",
          "arn:aws:cloudformation:${var.aws_region}:aws:transform/LanguageExtensions"
        ]
      },
      {
        Sid       = "ValidateTemplates"
        Effect    = "Allow"
        Action    = ["cloudformation:ValidateTemplate"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "LocateSamBucket"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation"]
        Resource = local.bucket_arns.artifacts
      },
      {
        Sid       = "ListEnvironmentSamArtifacts"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = local.bucket_arns.artifacts
        Condition = { StringLike = { "s3:prefix" = "sam/email/${environment}/*" } }
      },
      {
        Sid      = "DeleteEnvironmentSamArtifacts"
        Effect   = "Allow"
        Action   = ["s3:DeleteObject"]
        Resource = "${local.bucket_arns.artifacts}/sam/email/${environment}/*"
      },
      {
        Sid    = "PublishEnvironmentSamArtifacts"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:GetObjectVersion", "s3:PutObject",
          "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"
        ]
        Resource = "${local.bucket_arns.artifacts}/sam/email/${environment}/*"
      }
    ]
  } }
}

resource "aws_iam_policy" "email_sam" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-email-sam"
  path     = "/${var.project_name}/pipelines/"
  policy   = jsonencode(local.email_sam_policies[each.key])
  lifecycle {
    precondition {
      condition     = length(jsonencode(local.email_sam_policies[each.key])) <= 6144
      error_message = "A policy SAM ultrapassa o limite IAM de 6144 caracteres."
    }
  }
}

resource "aws_iam_role_policy_attachment" "email_sam" {
  for_each   = local.environments
  role       = aws_iam_role.email_pipeline[each.key].name
  policy_arn = aws_iam_policy.email_sam[each.key].arn
}
