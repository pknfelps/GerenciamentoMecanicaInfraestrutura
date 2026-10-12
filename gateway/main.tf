resource "aws_apigatewayv2_vpc_link" "api" {
  name               = "${local.name_prefix}-gateway"
  subnet_ids         = local.subnet_ids
  security_group_ids = [data.aws_security_group.gateway.id]

  lifecycle {
    precondition {
      condition = (
        length(local.subnet_ids) == 2 &&
        length(distinct([for subnet in data.aws_subnet.workload : subnet.availability_zone])) == 2 &&
        alltrue([for subnet in data.aws_subnet.workload : subnet.vpc_id == local.base["vpc-id"] && !subnet.map_public_ip_on_launch]) &&
        data.aws_security_group.gateway.vpc_id == local.base["vpc-id"] &&
        data.aws_security_group.gateway.name == "${local.name_prefix}-gateway"
      )
      error_message = "O VPC Link exige duas subnets privadas em AZs distintas e o SG reservado da VPC do ambiente."
    }
  }
}

resource "aws_api_gateway_rest_api" "gateway" {
  name              = "${local.name_prefix}-gateway"
  body              = jsonencode(local.definition)
  put_rest_api_mode = "overwrite"
  fail_on_warnings  = true
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  # Keep the VPC Link alive until the REST API and its integrations have been removed.
  depends_on = [aws_apigatewayv2_vpc_link.api]

  lifecycle {
    precondition {
      condition = (
        startswith(local.api_contract.openapi, "3.0.") &&
        startswith(local.auth_contract.openapi, "3.0.") &&
        local.auth["auth-contracts-version"] == "1.0.0" &&
        local.auth["openapi-key"] == "contracts/auth/${var.auth_commit}/openapi.json" &&
        local.auth["function-name"] == "${local.name_prefix}-auth" &&
        can(regex("^[1-9][0-9]*$", local.auth_version)) &&
        local.auth["invocation-arn"] == "arn:aws:lambda:${var.aws_region}:121754142617:function:${local.name_prefix}-auth:${local.auth_version}"
      )
      error_message = "Contratos OpenAPI 3.0 e versao numerica da Lambda implantada devem corresponder ao ambiente e commit selecionados."
    }
    precondition {
      condition = (
        length(local.api_operations) > 0 &&
        length(distinct([for route in local.api_operations : route.key])) == length(local.api_operations) &&
        length(local.auth_operations) == 1 &&
        alltrue([for route in local.auth_operations : route.key == "POST /customers/validate"]) &&
        length(setintersection(toset([for route in local.api_operations : route.key]), toset([for route in local.auth_operations : route.key]))) == 0 &&
        alltrue([for route in concat(local.api_operations, local.auth_operations) : !strcontains(route.path, "{proxy+")])
      )
      error_message = "Os contratos devem conter rotas explicitas sem conflitos e somente POST /customers/validate na autenticacao."
    }
    precondition {
      condition = (
        data.aws_lb.api.internal &&
        data.aws_lb.api.load_balancer_type == "network" &&
        data.aws_lb.api.name == "${local.name_prefix}-api" &&
        data.aws_lb.api.vpc_id == local.base["vpc-id"] &&
        data.aws_security_group.nlb.vpc_id == local.base["vpc-id"] &&
        contains(data.aws_lb.api.security_groups, data.aws_security_group.nlb.id) &&
        data.aws_lb_listener.api.protocol == "TCP" &&
        local.base["nlb-listener-port"] == "80" &&
        local.base["nlb-listener-protocol"] == "TCP" &&
        local.base["api-integration-uri"] == "http://${data.aws_lb.api.dns_name}:80"
      )
      error_message = "O destino deve ser o NLB interno da API do ambiente, com listener TCP 80 e URI HTTP correspondente."
    }
  }
}

resource "aws_lambda_permission" "validate_customer" {
  statement_id_prefix = "gateway-validate-"
  action              = "lambda:InvokeFunction"
  function_name       = local.auth["function-name"]
  qualifier           = local.auth_version
  principal           = "apigateway.amazonaws.com"
  source_account      = "121754142617"
  source_arn          = "${aws_api_gateway_rest_api.gateway.execution_arn}/${var.environment}/POST/customers/validate"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_deployment" "gateway" {
  rest_api_id = aws_api_gateway_rest_api.gateway.id
  triggers = {
    configuration = sha256(jsonencode({
      definition  = local.definition
      vpc_link_id = aws_apigatewayv2_vpc_link.api.id
      api_sha256  = filesha256(var.api_contract_file)
      auth_sha256 = filesha256(var.auth_contract_file)
    }))
  }
  depends_on = [aws_lambda_permission.validate_customer]
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${local.name_prefix}-gateway"
  retention_in_days = 7
}

resource "aws_api_gateway_stage" "gateway" {
  rest_api_id           = aws_api_gateway_rest_api.gateway.id
  deployment_id         = aws_api_gateway_deployment.gateway.id
  stage_name            = var.environment
  variables             = { vpcLinkId = aws_apigatewayv2_vpc_link.api.id }
  cache_cluster_enabled = false
  xray_tracing_enabled  = false
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId         = "$context.requestId"
      extendedRequestId = "$context.extendedRequestId"
      method            = "$context.httpMethod"
      route             = "$context.resourcePath"
      status            = "$context.status"
      durationMs        = "$context.responseLatency"
      integrationMs     = "$context.integrationLatency"
      responseLength    = "$context.responseLength"
    })
  }
}

resource "aws_api_gateway_method_settings" "gateway" {
  rest_api_id = aws_api_gateway_rest_api.gateway.id
  stage_name  = aws_api_gateway_stage.gateway.stage_name
  method_path = "*/*"
  settings {
    logging_level      = "OFF"
    data_trace_enabled = false
    metrics_enabled    = false
    caching_enabled    = false
  }
}
