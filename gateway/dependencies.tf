locals {
  name_prefix = "mecanica-${var.environment}"
  base_fields = toset([
    "vpc-id", "workload-subnet-ids", "gateway-security-group-id",
    "nlb-arn", "nlb-security-group-id", "nlb-listener-port", "nlb-listener-protocol", "api-integration-uri"
  ])
  auth_fields  = toset(["function-name", "function-version", "invocation-arn", "openapi-key", "auth-contracts-version"])
  base         = { for field, parameter in data.aws_ssm_parameter.base : field => nonsensitive(parameter.value) }
  auth         = { for field, parameter in data.aws_ssm_parameter.auth : field => nonsensitive(parameter.value) }
  subnet_ids   = toset(jsondecode(local.base["workload-subnet-ids"]))
  auth_version = local.auth["function-version"]
}
data "aws_ssm_parameter" "base" {
  for_each        = local.base_fields
  name            = "/mecanica/${var.environment}/base/v2/${each.key}"
  with_decryption = false
}
data "aws_ssm_parameter" "auth" {
  for_each        = local.auth_fields
  name            = "/mecanica/${var.environment}/auth/v2/${each.key}"
  with_decryption = false
}
data "aws_subnet" "workload" {
  for_each = local.subnet_ids
  id       = each.key
}
data "aws_security_group" "gateway" {
  id = local.base["gateway-security-group-id"]
}
data "aws_security_group" "nlb" {
  id = local.base["nlb-security-group-id"]
}
data "aws_lb" "api" {
  arn = local.base["nlb-arn"]
}
data "aws_lb_listener" "api" {
  load_balancer_arn = data.aws_lb.api.arn
  port              = 80
}
