variable "environment" {
  type = string
  validation {
    condition     = contains(["hom", "prd"], var.environment)
    error_message = "Use hom ou prd."
  }
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "O projeto utiliza us-east-1."
  }
}
variable "api_commit" {
  description = "SHA completo do contrato da API publicada e implantada."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.api_commit))
    error_message = "Informe um SHA completo de 40 caracteres minusculos."
  }
}
variable "auth_commit" {
  description = "SHA completo do contrato de autenticacao implantado."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.auth_commit))
    error_message = "Informe um SHA completo de 40 caracteres minusculos."
  }
}
variable "api_contract_file" {
  description = "Caminho relativo ao diretorio gateway do contrato verificado."
  type        = string
}
variable "auth_contract_file" {
  description = "Caminho relativo ao diretorio gateway do contrato verificado."
  type        = string
}
