locals {
  environments = toset(["hom", "prd"])
  buckets = {
    state     = "${var.project_name}-tfstate-${var.aws_account_id}-${var.aws_region}"
    artifacts = "${var.project_name}-artifacts-${var.aws_account_id}-${var.aws_region}"
  }
  bucket_arns = { for key, name in local.buckets : key => "arn:aws:s3:::${name}" }
  ecr_name    = "${var.project_name}/api"
  ecr_arn     = "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${local.ecr_name}"
  oidc_arn    = "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"

  # Artefatos são compartilhados, imutáveis e identificados pelo commit.
  components = {
    base = {
      repositories   = ["infra"]
      state_unit     = "base"
      artifact_read  = []
      artifact_write = []
      metadata_write = ["base"]
    }
    gateway = {
      # Reusable workflows executam no contexto do chamador (API/auth/infra).
      repositories   = ["infra", "api", "auth"]
      state_unit     = "gateway"
      artifact_read  = ["contracts/api", "contracts/auth"]
      artifact_write = ["contracts/gateway"]
      metadata_write = ["gateway"]
    }
    database = {
      repositories   = ["database"]
      state_unit     = "database"
      artifact_read  = []
      artifact_write = []
      metadata_write = ["database"]
    }
    api = {
      repositories   = ["api"]
      state_unit     = null
      artifact_read  = ["contracts/api", "packages/GerenciamentoMecanica.Auth.Contracts"]
      artifact_write = ["contracts/api", "packages/GerenciamentoMecanica.Auth.Contracts"]
      metadata_write = ["api"]
    }
    auth = {
      repositories   = ["auth"]
      state_unit     = "auth"
      artifact_read  = ["contracts/auth", "lambda", "packages/GerenciamentoMecanica.Auth.Contracts"]
      artifact_write = ["contracts/auth", "lambda"]
      metadata_write = ["auth"]
    }
  }
  roles = merge([
    for environment in local.environments : {
      for component, config in local.components : "${environment}-${component}" => merge(config, {
        environment = environment
        component   = component
        state_key   = config.state_unit == null ? null : "${environment}/${config.state_unit}/terraform.tfstate"
        subjects = [
          for repository in config.repositories :
          "${var.github_subject_prefixes[repository]}:environment:${environment}"
        ]
      })
    }
  ]...)
}