variable "new_relic_account_id" {
  description = "Account ID numérico do New Relic US. Não é uma credencial."
  type        = number

  validation {
    condition     = var.new_relic_account_id > 0 && floor(var.new_relic_account_id) == var.new_relic_account_id
    error_message = "Informe um Account ID positivo e inteiro do New Relic."
  }
}

variable "new_relic_alert_email" {
  description = "Destinatário dos alertas New Relic. Fornecido por NEW_RELIC_ALERT_EMAIL no Environment newrelic."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s,;]+@[^@\\s,;]+[.][^@\\s,;]+$", var.new_relic_alert_email))
    error_message = "Informe um único endereço de e-mail válido para os alertas New Relic."
  }
}
