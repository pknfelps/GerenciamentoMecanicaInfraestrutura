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

output "orders_notifications_alert_policy_id" {
  description = "ID da policy de falhas de notificação de OS."
  value       = newrelic_alert_policy.orders_notifications.id
}

output "orders_notifications_alert_condition_ids" {
  description = "IDs das condições de falha de notificação de OS por ambiente."
  value       = { for environment, condition in newrelic_nrql_alert_condition.orders_notifications : environment => condition.id }
}

output "node_cpu_alert_policy_id" {
  description = "ID da policy de CPU elevada do nó sobre CPU alocável."
  value       = newrelic_alert_policy.node_cpu.id
}

output "node_cpu_alert_condition_ids" {
  description = "IDs das condições de CPU elevada sobre CPU alocável por ambiente, avaliadas por nó."
  value       = { for environment, condition in newrelic_nrql_alert_condition.node_cpu : environment => condition.id }
}

output "node_memory_alert_policy_id" {
  description = "ID da policy de working set elevado do nó sobre memória alocável."
  value       = newrelic_alert_policy.node_memory.id
}

output "node_memory_alert_condition_ids" {
  description = "IDs das condições de working set elevado sobre memória alocável por ambiente, avaliadas por nó."
  value       = { for environment, condition in newrelic_nrql_alert_condition.node_memory : environment => condition.id }
}

output "api_availability_alert_policy_id" {
  description = "ID da policy da API sem réplica disponível."
  value       = newrelic_alert_policy.api_availability.id
}

output "api_availability_alert_condition_ids" {
  description = "IDs das condições da API sem réplica disponível por ambiente."
  value       = { for environment, condition in newrelic_nrql_alert_condition.api_availability : environment => condition.id }
}
