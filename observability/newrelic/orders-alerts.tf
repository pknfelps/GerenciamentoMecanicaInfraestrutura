resource "newrelic_alert_policy" "orders_processing" {
  account_id          = var.new_relic_account_id
  name                = "Mecânica — Falhas de processamento de OS"
  incident_preference = "PER_CONDITION"
}

resource "newrelic_nrql_alert_condition" "orders_processing" {
  for_each = toset(["hom", "prd"])

  account_id = var.new_relic_account_id
  policy_id  = newrelic_alert_policy.orders_processing.id
  type       = "static"
  name       = "Mecânica — ${each.key} — Falha técnica no processamento de OS"
  description = join(" ", [
    "Pelo menos uma falha técnica nas ações HTTP de OS em cinco minutos no ambiente ${each.key}.",
    "Erros de negócio e cancelamentos do cliente não entram nesta métrica.",
    "O encerramento após dez minutos sem pontos indica ausência de sinal e não comprova recuperação da API."
  ])
  runbook_url = "https://github.com/pknfelps/GerenciamentoMecanicaInfraestrutura/blob/main/observability/newrelic/README.md#alerta-de-processamento-de-os"
  enabled     = true

  nrql {
    query = <<-NRQL
      SELECT sum(`mecanica.orders.processing.failures`)
      FROM Metric
      WHERE metricName = 'mecanica.orders.processing.failures'
        AND `service.name` = 'mecanica-api'
        AND `deployment.environment.name` = '${each.key}'
    NRQL
  }

  aggregation_window             = 300
  aggregation_method             = "event_timer"
  aggregation_timer              = 60
  fill_option                    = "none"
  expiration_duration            = 600
  close_violations_on_expiration = true
  open_violation_on_expiration   = false
  # Required by the provider; use the longest native limit, independently of signal expiration.
  violation_time_limit_seconds = 2592000

  critical {
    operator              = "above_or_equals"
    threshold             = 1
    threshold_duration    = 300
    threshold_occurrences = "AT_LEAST_ONCE"
  }
}

resource "newrelic_notification_destination" "alerts_email" {
  account_id = var.new_relic_account_id
  name       = "mecanica-alertas-email"
  type       = "EMAIL"

  property {
    key   = "email"
    value = var.new_relic_alert_email
  }
}

resource "newrelic_notification_channel" "orders_processing" {
  account_id     = var.new_relic_account_id
  name           = "mecanica-os-falha-tecnica-email"
  type           = "EMAIL"
  product        = "IINT"
  destination_id = newrelic_notification_destination.alerts_email.id

  property {
    key   = "subject"
    value = "Mecânica — OS — {{state}} — {{#each accumulations.conditionName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}"
  }

  property {
    key   = "customDetailsEmail"
    value = <<-DETAILS
      Condição e ambiente: {{#each accumulations.conditionName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}
      Incidente: {{issuePageUrl}}
      Consulte o dashboard de ordens e selecione o ambiente indicado na condição: ${newrelic_one_dashboard_json.orders.permalink}
      Investigue a operação e os logs sanitizados na janela do incidente; não envie documentos, tokens ou credenciais.
      Encerramento por dez minutos sem pontos significa ausência de sinal, não recuperação comprovada da API.
    DETAILS
  }
}

resource "newrelic_workflow" "orders_processing" {
  account_id            = var.new_relic_account_id
  name                  = "mecanica-os-falha-tecnica"
  enabled               = true
  enrichments_enabled   = false
  muting_rules_handling = "DONT_NOTIFY_FULLY_OR_PARTIALLY_MUTED_ISSUES"

  issues_filter {
    name = "Somente falhas de processamento de OS"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.orders_processing.id]
    }
  }

  destination {
    channel_id            = newrelic_notification_channel.orders_processing.id
    notification_triggers = ["ACTIVATED", "CLOSED"]
  }
}
