output "shared_resources" {
  description = "Identificadores persistentes; nomes previstos não comprovam existência antes do apply."
  value = {
    state_bucket     = local.buckets.state
    artifacts_bucket = local.buckets.artifacts
    ecr_repository   = aws_ecr_repository.api.repository_url
    oidc_provider    = local.oidc_arn
  }
}

output "backend_configs" {
  description = "Uma chave por unidade/ambiente; usar o workspace default."
  value = {
    for key, config in local.roles : key => {
      bucket               = local.buckets.state
      key                  = config.state_key
      workspace_key_prefix = "${config.environment}/${config.state_unit}/workspaces"
      region               = var.aws_region
      encrypt              = true
      use_lockfile         = true
    } if config.state_key != null
  }
}

output "bootstrap_backend_config" {
  value = {
    bucket       = local.buckets.state
    key          = "shared/bootstrap/terraform.tfstate"
    region       = var.aws_region
    encrypt      = true
    use_lockfile = true
  }
}

output "github_environment_variables" {
  description = "Variáveis reais a preencher no GitHub após apply, por componente e ambiente."
  value = {
    for environment in local.environments : environment => {
      infra = {
        AWS_REGION           = var.aws_region
        AWS_BASE_ROLE_ARN    = aws_iam_role.pipeline["${environment}-base"].arn
        AWS_GATEWAY_ROLE_ARN = aws_iam_role.pipeline["${environment}-gateway"].arn
        TF_STATE_BUCKET      = local.buckets.state
        ARTIFACTS_BUCKET     = local.buckets.artifacts
      }
      database = {
        AWS_REGION      = var.aws_region
        AWS_ROLE_ARN    = aws_iam_role.pipeline["${environment}-database"].arn
        TF_STATE_BUCKET = local.buckets.state
      }
      api = {
        AWS_REGION       = var.aws_region
        AWS_ROLE_ARN     = aws_iam_role.pipeline["${environment}-api"].arn
        ARTIFACTS_BUCKET = local.buckets.artifacts
      }
      auth = {
        AWS_REGION       = var.aws_region
        AWS_ROLE_ARN     = aws_iam_role.pipeline["${environment}-auth"].arn
        TF_STATE_BUCKET  = local.buckets.state
        ARTIFACTS_BUCKET = local.buckets.artifacts
      }
    }
  }
}