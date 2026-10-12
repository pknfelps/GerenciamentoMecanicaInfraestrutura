# Shared regional configuration stays in the persistent bootstrap.
resource "aws_iam_service_linked_role" "api_gateway" {
  aws_service_name = "ops.apigateway.amazonaws.com"
  lifecycle { prevent_destroy = true }
}
resource "aws_iam_role" "api_gateway_logs" {
  name = "${var.project_name}-apigateway-logs"
  path = "/${var.project_name}/runtime/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  lifecycle { prevent_destroy = true }
}
resource "aws_iam_role_policy" "api_gateway_logs" {
  name = "gateway-access-logs"
  role = aws_iam_role.api_gateway_logs.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "GatewayAccessAndValidationLogs",
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ],
        "Resource" : [
          # API Gateway validates the regional role by writing to this technical log group.
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/apigateway/welcome",
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/apigateway/welcome:*",
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/apigateway/${var.project_name}-hom-gateway",
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/apigateway/${var.project_name}-prd-gateway",
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/apigateway/${var.project_name}-hom-gateway:*",
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/apigateway/${var.project_name}-prd-gateway:*"
        ]
      },
      {
        "Sid" : "LocateGatewayLogGroups",
        "Effect" : "Allow",
        "Action" : [
          "logs:DescribeLogGroups"
        ],
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : {
            "aws:RequestedRegion" : "${var.aws_region}"
          }
        }
      }
    ]
  })
}
resource "aws_api_gateway_account" "logging" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_logs.arn
  depends_on          = [aws_iam_role_policy.api_gateway_logs]
  lifecycle { prevent_destroy = true }
}
