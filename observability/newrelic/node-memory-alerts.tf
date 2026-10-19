resource "newrelic_alert_policy" "node_memory" {
  account_id          = var.new_relic_account_id
  name                = "Mecânica — Memória elevada do nó"
  incident_preference = "PER_CONDITION_AND_TARGET"
}

resource "newrelic_nrql_alert_condition" "node_memory" {
  for_each = toset(["hom", "prd"])

  account_id = var.new_relic_account_id
  policy_id  = newrelic_alert_policy.node_memory.id
  type       = "static"
  name       = "Mecânica — ${each.key} — Working set do nó acima de 85% da memória alocável"
  description = join(" ", [
    "Working set médio por nó acima de 85% da memória alocável durante cinco minutos consecutivos no ambiente ${each.key}.",
    "Cada janela de um minuto usa o working set médio e a memória alocável mais recente da mesma janela; memória alocável não é capacidade física total.",
    "O percentual elevado não comprova OOM ou MemoryPressure. O kubeletstats cobre somente o nó onde o Collector executa.",
    "Encerramento após dez minutos sem pontos indica ausência de sinal, não recuperação comprovada."
  ])
  runbook_url = "https://github.com/pknfelps/GerenciamentoMecanicaInfraestrutura/blob/main/observability/newrelic/README.md#alerta-de-memória-elevada-do-nó"
  enabled     = true

  nrql {
    query = <<-NRQL
      SELECT 100 * average(`k8s.node.memory.working_set`)
        / latest(`k8s.node.allocatable_memory`)
      FROM Metric
      WHERE `deployment.environment.name` = '${each.key}'
        AND `k8s.cluster.name` = 'mecanica-${each.key}-eks'
        AND metricName IN (
          'k8s.node.memory.working_set',
          'k8s.node.allocatable_memory'
        )
      FACET `k8s.node.name`
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
    operator              = "above"
    threshold             = 85
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }
}

resource "newrelic_notification_channel" "node_memory" {
  account_id     = var.new_relic_account_id
  name           = "mecanica-no-memoria-alocavel-elevada-email"
  type           = "EMAIL"
  product        = "IINT"
  destination_id = newrelic_notification_destination.alerts_email.id

  property {
    key   = "subject"
    value = "Mecânica — Working set do nó sobre memória alocável — {{state}} — {{#each accumulations.conditionName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}"
  }

  property {
    key   = "customDetailsEmail"
    value = <<-DETAILS
      Estado: {{state}}
      Condição e ambiente: {{#each accumulations.conditionName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}
      Incidente: {{issuePageUrl}}
      Identifique o nó pela faceta k8s.node.name no incidente e consulte o dashboard Operação da API e Kubernetes no mesmo ambiente e período: ${newrelic_one_dashboard_json.operations.permalink}
      Confira working set médio e memória alocável da mesma janela, além dos pods, containers, reinícios e condição MemoryPressure. O percentual usa memória alocável, não capacidade física total, requests ou limits.
      Percentual elevado não comprova OOM ou MemoryPressure. O kubeletstats cobre somente o nó onde o Collector executa.
      Encerramento por dez minutos sem pontos significa ausência de sinal, não recuperação comprovada.
    DETAILS
  }
}

resource "newrelic_workflow" "node_memory" {
  account_id            = var.new_relic_account_id
  name                  = "mecanica-no-memoria-alocavel-elevada"
  enabled               = true
  enrichments_enabled   = false
  muting_rules_handling = "DONT_NOTIFY_FULLY_OR_PARTIALLY_MUTED_ISSUES"

  issues_filter {
    name = "Somente memória elevada do nó"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.node_memory.id]
    }
  }

  destination {
    channel_id            = newrelic_notification_channel.node_memory.id
    notification_triggers = ["ACTIVATED", "CLOSED"]
  }
}
