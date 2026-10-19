output "operations_dashboard_guid" {
  description = "GUID do dashboard persistente de operação."
  value       = newrelic_one_dashboard_json.operations.guid
}

output "operations_dashboard_permalink" {
  description = "Link do dashboard de operação no New Relic."
  value       = newrelic_one_dashboard_json.operations.permalink
}

output "orders_dashboard_guid" {
  description = "GUID do dashboard persistente de ordens de serviço."
  value       = newrelic_one_dashboard_json.orders.guid
}

output "orders_dashboard_permalink" {
  description = "Link do dashboard de ordens de serviço no New Relic."
  value       = newrelic_one_dashboard_json.orders.permalink
}

output "integrations_dashboard_guid" {
  description = "GUID do dashboard persistente de integrações e autenticação."
  value       = newrelic_one_dashboard_json.integrations.guid
}

output "integrations_dashboard_permalink" {
  description = "Link do dashboard de integrações e autenticação no New Relic."
  value       = newrelic_one_dashboard_json.integrations.permalink
}

output "orders_processing_alert_policy_id" {
  description = "ID da policy de falhas técnicas de processamento de OS."
  value       = newrelic_alert_policy.orders_processing.id
}

output "orders_processing_alert_condition_ids" {
  description = "IDs das condições de falha técnica de OS por ambiente."
  value       = { for environment, condition in newrelic_nrql_alert_condition.orders_processing : environment => condition.id }
}
