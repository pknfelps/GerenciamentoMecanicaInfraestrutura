variable "new_relic_account_id" {
  description = "Account ID numérico do New Relic US. Não é uma credencial."
  type        = number

  validation {
    condition     = var.new_relic_account_id > 0 && floor(var.new_relic_account_id) == var.new_relic_account_id
    error_message = "Informe um Account ID positivo e inteiro do New Relic."
  }
}
