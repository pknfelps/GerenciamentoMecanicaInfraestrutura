variable "aws_account_id" {
  description = "Conta de destino; o provider recusa credenciais de outra conta."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Informe o ID AWS de 12 dígitos."
  }
}

variable "aws_region" {
  type        = string
  description = "Região do bootstrap compartilhado."
  default     = "us-east-1"
  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "O projeto utiliza us-east-1."
  }
}

variable "project_name" {
  type        = string
  description = "Prefixo dos recursos persistentes, sem ambiente."
  default     = "mecanica"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project_name))
    error_message = "Use de 3 a 20 letras minúsculas, números ou hífens, iniciando com letra."
  }
}

variable "github_subject_prefixes" {
  description = "Prefixos exatos do sub OIDC, sem :environment:. Conferir claims reais antes de aplicar; não aceita curingas."
  type = object({
    api      = string
    infra    = string
    database = string
    auth     = string
  })
  validation {
    condition = alltrue([
      for prefix in values(var.github_subject_prefixes) :
      can(regex("^repo:[A-Za-z0-9_-]+(@[0-9]+)?/[A-Za-z0-9_.-]+(@[0-9]+)?$", prefix))
    ])
    error_message = "Use repo:owner/repo ou repo:owner@ID/repo@ID, sem wildcard ou contexto."
  }
  validation {
    condition     = length(distinct(values(var.github_subject_prefixes))) == 4
    error_message = "Cada componente deve identificar um repositório distinto."
  }
}

variable "existing_github_oidc_provider_arn" {
  description = "ARN de provider GitHub já gerenciado fora deste estado; null cria um provider. Não alternar após criação sem migração de estado."
  type        = string
  default     = null
  validation {
    condition = var.existing_github_oidc_provider_arn == null ? true : (
      var.existing_github_oidc_provider_arn == "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
    )
    error_message = "O provider existente deve ser do GitHub e da conta de destino."
  }
}