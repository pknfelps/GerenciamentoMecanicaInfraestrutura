resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_github_oidc_provider_arn == null ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # O GitHub é validado pela cadeia de CAs confiáveis da AWS, sem thumbprint fixo.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "pipeline" {
  for_each             = local.roles
  name                 = "${var.project_name}-${each.key}-github"
  path                 = "/${var.project_name}/pipelines/"
  description          = "GitHub Actions: ${each.value.component} / ${each.value.environment}"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubEnvironment"
      Effect    = "Allow"
      Principal = { Federated = local.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = each.value.subjects
          "token.actions.githubusercontent.com:ref" = each.value.environment == "hom" ? "refs/heads/develop" : "refs/heads/main"
        }
      }
    }]
  })
  tags = {
    Environment = each.value.environment
    Component   = each.value.component
  }
  depends_on = [aws_iam_openid_connect_provider.github]
}

# Permissões do bootstrap: estado, artefatos, publicação ECR e metadados.
# Provisionamento de workloads e IAM/PassRole serão revisados em E2/E3.
resource "aws_iam_role_policy" "pipeline" {
  for_each = local.roles
  name     = "bootstrap-access"
  role     = aws_iam_role.pipeline[each.key].id
  policy   = jsonencode(local.pipeline_policies[each.key])
}

locals {
  pipeline_policies = {
    for key, config in local.roles : key => {
      Version = "2012-10-17"
      Statement = concat(
        jsondecode(config.state_key == null ? "[]" : jsonencode([
          {
            Sid      = "LocateStateBucket"
            Effect   = "Allow"
            Action   = ["s3:GetBucketLocation"]
            Resource = [local.bucket_arns.state]
          },
          {
            Sid      = "ListOwnState"
            Effect   = "Allow"
            Action   = ["s3:ListBucket"]
            Resource = [local.bucket_arns.state]
            Condition = { StringEquals = { "s3:prefix" = [
              config.state_key, "${config.state_key}.tflock", "${config.environment}/${config.state_unit}/workspaces/"
            ] } }
          },
          {
            Sid      = "ReadWriteOwnState"
            Effect   = "Allow"
            Action   = ["s3:GetObject", "s3:PutObject"]
            Resource = ["${local.bucket_arns.state}/${config.state_key}"]
          },
          {
            Sid      = "OwnStateLock"
            Effect   = "Allow"
            Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
            Resource = ["${local.bucket_arns.state}/${config.state_key}.tflock"]
          }
        ])),
        length(config.artifact_read) == 0 ? [] : [{
          Sid      = "ReadArtifacts"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = [for prefix in config.artifact_read : "${local.bucket_arns.artifacts}/${prefix}/*"]
        }],
        length(config.artifact_write) == 0 ? [] : [{
          Sid      = "PublishArtifacts"
          Effect   = "Allow"
          Action   = ["s3:PutObject"]
          Resource = [for prefix in config.artifact_write : "${local.bucket_arns.artifacts}/${prefix}/*"]
        }],
        [{
          Sid      = "ReadEnvironmentMetadata"
          Effect   = "Allow"
          Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
          Resource = ["arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/${config.environment}/*"]
          }, {
          Sid      = "PublishOwnMetadata"
          Effect   = "Allow"
          Action   = ["ssm:PutParameter", "ssm:AddTagsToResource", "ssm:DeleteParameter"]
          Resource = [for component in config.metadata_write : "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/${config.environment}/${component}/v1/*"]
        }],
        config.component != "api" ? [] : [{
          Sid      = "EcrAuthentication"
          Effect   = "Allow"
          Action   = ["ecr:GetAuthorizationToken"]
          Resource = ["*"]
          }, {
          Sid    = "PublishApiImage"
          Effect = "Allow"
          Action = [
            "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
            "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"
          ]
          Resource = [local.ecr_arn]
        }]
      )
    }
  }
}