resource "newrelic_alert_policy" "api_availability" {
  account_id          = var.new_relic_account_id
  name                = "Mecânica — API sem réplica disponível"
  incident_preference = "PER_CONDITION"
}

resource "newrelic_nrql_alert_condition" "api_availability" {
  for_each = toset(["hom", "prd"])

  account_id = var.new_relic_account_id
  policy_id  = newrelic_alert_policy.api_availability.id
  type       = "static"
  name       = "Mecânica — ${each.key} — API sem réplica disponível por dois minutos"
  description = join(" ", [
    "O Deployment default/deploy-gerenciamento-api não apresentou réplica disponível em duas janelas consecutivas de um minuto no ambiente ${each.key}.",
    "Cada janela usa o máximo observado; escala intencional para zero também pode disparar. Silenciar manualmente durante manutenção planejada.",
    "Ausência de métrica não é zero: exclusão do Deployment ou interrupção da coleta não garante detecção de indisponibilidade por esta condição.",
    "Encerramento após dez minutos sem pontos indica ausência de sinal, não recuperação. Uma réplica disponível não comprova funcionamento ponta a ponta."
  ])
  runbook_url = "https://github.com/pknfelps/GerenciamentoMecanicaInfraestrutura/blob/main/observability/newrelic/README.md#alerta-de-api-sem-réplica-disponível"
  enabled     = true

  nrql {
    query = <<-NRQL
      SELECT max(`k8s.deployment.available`)
      FROM Metric
      WHERE metricName = 'k8s.deployment.available'
        AND `deployment.environment.name` = '${each.key}'
        AND `k8s.cluster.name` = 'mecanica-${each.key}-eks'
        AND `k8s.namespace.name` = 'default'
        AND `k8s.deployment.name` = 'deploy-gerenciamento-api'
    NRQL
  }

  aggregation_window             = 60
  aggregation_method             = "event_flow"
  aggregation_delay              = 60
  fill_option                    = "none"
  expiration_duration            = 600
  close_violations_on_expiration = true
  open_violation_on_expiration   = false
  # Required by the provider; use the longest native limit, independently of signal expiration.
  violation_time_limit_seconds = 2592000

  critical {
    operator              = "below"
    threshold             = 1
    threshold_duration    = 120
    threshold_occurrences = "ALL"
  }
}

resource "newrelic_notification_channel" "api_availability" {
  account_id     = var.new_relic_account_id
  name           = "mecanica-api-sem-replica-disponivel-email"
  type           = "EMAIL"
  product        = "IINT"
  destination_id = newrelic_notification_destination.alerts_email.id

  property {
    key   = "subject"
    value = "Mecânica — API sem réplica disponível — {{state}} — {{#each accumulations.conditionName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}"
  }

  property {
    key   = "customDetailsEmail"
    value = <<-DETAILS
      Estado: {{state}}
      Condição e ambiente: {{#each accumulations.conditionName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}
      Incidente: {{issuePageUrl}}
      Consulte o dashboard Operação da API e Kubernetes no mesmo ambiente e período: ${newrelic_one_dashboard_json.operations.permalink}
      Confira réplicas desejadas/disponíveis, pods, readiness, reinícios e eventos do Deployment default/deploy-gerenciamento-api.
      Escala intencional para zero também pode disparar; silenciar manualmente durante manutenção planejada. Não há recuperação automática por este alerta.
      Ausência de métrica não é zero. Encerramento por dez minutos sem pontos não comprova recuperação; uma réplica disponível não comprova funcionamento ponta a ponta.
    DETAILS
  }
}

resource "newrelic_workflow" "api_availability" {
  account_id            = var.new_relic_account_id
  name                  = "mecanica-api-sem-replica-disponivel"
  enabled               = true
  enrichments_enabled   = false
  muting_rules_handling = "DONT_NOTIFY_FULLY_OR_PARTIALLY_MUTED_ISSUES"

  issues_filter {
    name = "Somente API sem réplica disponível"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.api_availability.id]
    }
  }

  destination {
    channel_id            = newrelic_notification_channel.api_availability.id
    notification_triggers = ["ACTIVATED", "CLOSED"]
  }
}
