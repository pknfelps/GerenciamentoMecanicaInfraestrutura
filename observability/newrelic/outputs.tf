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
