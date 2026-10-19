resource "newrelic_alert_policy" "node_cpu" {
  account_id          = var.new_relic_account_id
  name                = "Mecânica — CPU elevada do nó"
  incident_preference = "PER_CONDITION_AND_TARGET"
}

resource "newrelic_nrql_alert_condition" "node_cpu" {
  for_each = toset(["hom", "prd"])

  account_id = var.new_relic_account_id
  policy_id  = newrelic_alert_policy.node_cpu.id
  type       = "static"
  name       = "Mecânica — ${each.key} — CPU do nó acima de 80% da CPU alocável"
  description = join(" ", [
    "CPU média utilizada por nó acima de 80% da CPU alocável durante cinco minutos consecutivos no ambiente ${each.key}.",
    "Cada janela de um minuto usa a CPU média utilizada e a CPU alocável mais recente da mesma janela; CPU alocável não é capacidade total.",
    "O kubeletstats cobre somente o nó onde o Collector executa; esta condição não amplia a cobertura.",
    "Encerramento após dez minutos sem pontos indica ausência de sinal, não recuperação comprovada."
  ])
  runbook_url = "https://github.com/pknfelps/GerenciamentoMecanicaInfraestrutura/blob/main/observability/newrelic/README.md#alerta-de-cpu-elevada-do-nó"
  enabled     = true

  nrql {
    query = <<-NRQL
      SELECT 100 * average(`k8s.node.cpu.usage`)
        / latest(`k8s.node.allocatable_cpu`)
      FROM Metric
      WHERE `deployment.environment.name` = '${each.key}'
        AND `k8s.cluster.name` = 'mecanica-${each.key}-eks'
        AND metricName IN (
          'k8s.node.cpu.usage',
          'k8s.node.allocatable_cpu'
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
    threshold             = 80
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }
}

resource "newrelic_notification_channel" "node_cpu" {
  account_id     = var.new_relic_account_id
  name           = "mecanica-no-cpu-alocavel-elevada-email"
  type           = "EMAIL"
  product        = "IINT"
  destination_id = newrelic_notification_destination.alerts_email.id

  property {
    key   = "subject"
    value = "Mecânica — CPU do nó sobre CPU alocável — {{state}} — {{#each accumulations.conditionName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}"
  }

  property {
    key   = "customDetailsEmail"
    value = <<-DETAILS
      Estado: {{state}}
      Condição e ambiente: {{#each accumulations.conditionName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}
      Incidente: {{issuePageUrl}}
      Identifique o nó pela faceta k8s.node.name no incidente e consulte o dashboard Operação da API e Kubernetes no mesmo ambiente e período: ${newrelic_one_dashboard_json.operations.permalink}
      Confira CPU média utilizada e CPU alocável da mesma janela, além dos pods e containers do nó. O percentual usa CPU alocável, não capacidade total, requests ou limits.
      O kubeletstats cobre somente o nó onde o Collector executa. Encerramento por dez minutos sem pontos significa ausência de sinal, não recuperação comprovada.
    DETAILS
  }
}

resource "newrelic_workflow" "node_cpu" {
  account_id            = var.new_relic_account_id
  name                  = "mecanica-no-cpu-alocavel-elevada"
  enabled               = true
  enrichments_enabled   = false
  muting_rules_handling = "DONT_NOTIFY_FULLY_OR_PARTIALLY_MUTED_ISSUES"

  issues_filter {
    name = "Somente CPU elevada do nó"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.node_cpu.id]
    }
  }

  destination {
    channel_id            = newrelic_notification_channel.node_cpu.id
    notification_triggers = ["ACTIVATED", "CLOSED"]
  }
}
