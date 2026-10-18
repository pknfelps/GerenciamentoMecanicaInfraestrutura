output "operations_dashboard_guid" {
  description = "GUID do dashboard persistente de operação."
  value       = newrelic_one_dashboard_json.operations.guid
}

output "operations_dashboard_permalink" {
  description = "Link do dashboard de operação no New Relic."
  value       = newrelic_one_dashboard_json.operations.permalink
}
