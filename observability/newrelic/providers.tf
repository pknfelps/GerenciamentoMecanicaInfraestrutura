provider "newrelic" {
  account_id = var.new_relic_account_id
  region     = "US"
  # NEW_RELIC_API_KEY is read by the provider from the current process.
}
