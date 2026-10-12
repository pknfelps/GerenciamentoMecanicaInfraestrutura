locals {
  configuration = {
    "rest-api-id"         = aws_api_gateway_rest_api.gateway.id
    "vpc-link-id"         = aws_apigatewayv2_vpc_link.api.id
    "stage-name"          = aws_api_gateway_stage.gateway.stage_name
    "endpoint"            = aws_api_gateway_stage.gateway.invoke_url
    "api-openapi-key"     = "contracts/api/${var.api_commit}/openapi.json"
    "auth-openapi-key"    = "contracts/auth/${var.auth_commit}/openapi.json"
    "auth-invocation-arn" = local.auth["invocation-arn"]
  }
}
resource "aws_ssm_parameter" "configuration" {
  for_each = local.configuration
  name     = "/mecanica/${var.environment}/gateway/v2/${each.key}"
  type     = "String"
  value    = each.value
}
output "endpoint" {
  value = aws_api_gateway_stage.gateway.invoke_url
}
output "configuration" {
  value = local.configuration
}
output "contract_revisions" {
  value = {
    api_commit  = var.api_commit
    auth_commit = var.auth_commit
    api_sha256  = filesha256(var.api_contract_file)
    auth_sha256 = filesha256(var.auth_contract_file)
  }
}
