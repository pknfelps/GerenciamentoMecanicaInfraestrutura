locals {
  api_contract  = jsondecode(file(var.api_contract_file))
  auth_contract = jsondecode(file(var.auth_contract_file))
  http_methods  = toset(["get", "post", "put", "patch", "delete", "head", "options"])
  private_paths = toset(["/health/live", "/health/startup", "/health/ready"])

  api_operations = flatten([
    for path, item in local.api_contract.paths : [
      for method, operation in item : {
        key       = "${upper(method)} ${path}"
        path      = path
        method    = method
        operation = operation
        # Path declarations are sufficient for proxy routing; query/header/body pass through.
        parameters = [for name in regexall("\\{([^{}]+)\\}", path) : {
          name     = name[0]
          in       = "path"
          required = true
          schema   = { type = "string" }
        }]
      } if contains(local.http_methods, method)
    ] if !contains(local.private_paths, path)
  ])
  auth_operations = flatten([
    for path, item in local.auth_contract.paths : [
      for method, operation in item : {
        key       = "${upper(method)} ${path}"
        path      = path
        method    = method
        operation = operation
      } if contains(local.http_methods, method)
    ]
  ])

  # This is an AWS routing definition, not a replacement for the published business contracts.
  api_paths = {
    for path in distinct([for route in local.api_operations : route.path]) : path => {
      for route in local.api_operations : route.method => {
        parameters = route.parameters
        security   = []
        responses = { for status, response in route.operation.responses : status => {
          description = try(response.description, "Resposta do backend")
        } }
        "x-amazon-apigateway-integration" = {
          type                = "http_proxy"
          httpMethod          = upper(route.method)
          uri                 = "${local.base["api-integration-uri"]}${route.path}"
          connectionType      = "VPC_LINK"
          connectionId        = "$${stageVariables.vpcLinkId}"
          integrationTarget   = local.base["nlb-arn"]
          passthroughBehavior = "when_no_match"
          timeoutInMillis     = 29000
          requestParameters = {
            for parameter in route.parameters :
            "integration.request.path.${parameter.name}" => "method.request.path.${parameter.name}"
          }
        }
      } if route.path == path
    }
  }
  auth_paths = {
    for path in distinct([for route in local.auth_operations : route.path]) : path => {
      for route in local.auth_operations : route.method => {
        security = []
        responses = { for status, response in route.operation.responses : status => {
          description = try(response.description, "Resposta da autenticacao")
        } }
        "x-amazon-apigateway-integration" = {
          type            = "aws_proxy"
          httpMethod      = "POST"
          uri             = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${local.auth["invocation-arn"]}/invocations"
          timeoutInMillis = 29000
        }
      } if route.path == path
    }
  }
  definition = {
    openapi = "3.0.1"
    info    = { title = "${local.name_prefix}-gateway", version = "1.0.0" }
    paths = {
      for path in setunion(toset(keys(local.api_paths)), toset(keys(local.auth_paths))) :
      path => merge(try(local.api_paths[path], {}), try(local.auth_paths[path], {}))
    }
  }
}
