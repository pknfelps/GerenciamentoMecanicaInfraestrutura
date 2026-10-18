resource "newrelic_one_dashboard_json" "operations" {
  account_id = var.new_relic_account_id
  json = templatefile("${path.module}/dashboards/operations.json.tftpl", {
    account_id = var.new_relic_account_id
  })

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = terraform.workspace == "default"
      error_message = "A unidade persistente New Relic deve usar o workspace default."
    }
  }
}
