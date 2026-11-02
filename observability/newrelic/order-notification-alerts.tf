resource "newrelic_alert_policy" "orders_notifications" {
  account_id          = var.new_relic_account_id
  name                = "Mecânica — Falhas de notificação de OS"
  incident_preference = "PER_CONDITION"
}

resource "newrelic_nrql_alert_condition" "orders_notifications" {
  for_each = toset(["hom", "prd"])

  account_id = var.new_relic_account_id
  policy_id  = newrelic_alert_policy.orders_notifications.id
  type       = "static"
  name       = "Mecânica — ${each.key} — Falha de notificação de OS"
  description = join(" ", [
    "Pelo menos uma falha no fluxo de notificação de OS em cinco minutos no ambiente ${each.key}, incluindo consultas, montagem e envio.",
    "Em hom/prd, a API invoca a EmailFunction, que transmite ao SMTP4dev privado; sucesso em mode=smtp significa captura, sem entrega externa ao destinatário. Registros históricos em mode=simulated representam somente simulação.",
    "A falha tratada da notificação não desfaz a operação persistida da OS.",
    "Encerramento após dez minutos sem pontos indica ausência de sinal, não recuperação, entrega posterior ou reprocessamento."
  ])
  runbook_url = "https://github.com/pknfelps/GerenciamentoMecanicaInfraestrutura/blob/main/observability/newrelic/README.md#alerta-de-notificação-de-os"
  enabled     = true

  nrql {
    query = <<-NRQL
      SELECT sum(`mecanica.orders.notifications`)
      FROM Metric
      WHERE metricName = 'mecanica.orders.notifications'
        AND `service.name` = 'mecanica-api'
        AND `deployment.environment.name` = '${each.key}'
        AND outcome = 'failure'
        AND `notification.type` IN ('budget_available', 'status_changed')
        AND mode IN ('smtp', 'simulated')
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

resource "newrelic_notification_channel" "orders_notifications" {
  account_id     = var.new_relic_account_id
  name           = "mecanica-os-falha-notificacao-email"
  type           = "EMAIL"
  product        = "IINT"
  destination_id = newrelic_notification_destination.alerts_email.id

  property {
    key   = "subject"
    value = "Mecânica — Notificação de OS — {{state}} — {{#each accumulations.conditionName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}"
  }

  property {
    key   = "customDetailsEmail"
    value = <<-DETAILS
      Estado: {{state}}
      Condição e ambiente: {{#each accumulations.conditionName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}
      Incidente: {{issuePageUrl}}
      Consulte o bloco de notificações do dashboard Integrações e autenticação, no ambiente e período do incidente: ${newrelic_one_dashboard_json.integrations.permalink}
      Investigue tipo/modo da notificação, logs sanitizados e traces disponíveis; não envie documentos, tokens, credenciais ou mensagens originais de exceção.
      Em hom/prd, a API invoca a EmailFunction para captura no SMTP4dev privado. Sucesso em mode=smtp não comprova entrega externa; registros históricos em mode=simulated representam somente simulação. Falha de notificação não desfaz a operação persistida da OS.
      Encerramento por dez minutos sem pontos significa ausência de sinal, não recuperação, entrega posterior ou reprocessamento.
    DETAILS
  }
}

resource "newrelic_workflow" "orders_notifications" {
  account_id            = var.new_relic_account_id
  name                  = "mecanica-os-falha-notificacao"
  enabled               = true
  enrichments_enabled   = false
  muting_rules_handling = "DONT_NOTIFY_FULLY_OR_PARTIALLY_MUTED_ISSUES"

  issues_filter {
    name = "Somente falhas de notificação de OS"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.orders_notifications.id]
    }
  }

  destination {
    channel_id            = newrelic_notification_channel.orders_notifications.id
    notification_triggers = ["ACTIVATED", "CLOSED"]
  }
}
