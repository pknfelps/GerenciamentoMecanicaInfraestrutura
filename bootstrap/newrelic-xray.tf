# A integração consulta X-Ray diretamente; não utiliza os Collectors nem a License Key.
locals {
  newrelic_xray_trust_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "NewRelicUSAccount"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::754728514883:root" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = var.new_relic_account_id } }
    }]
  }
  newrelic_xray_read_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ReadRegionalXRayTraces"
      Effect    = "Allow"
      Action    = ["xray:Get*", "xray:BatchGet*"]
      Resource  = "*"
      Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
    }]
  }
}

resource "aws_iam_role" "newrelic_xray" {
  name                 = "${var.project_name}-newrelic-xray"
  path                 = "/${var.project_name}/observability/"
  description          = "New Relic US: leitura regional de traces nativos X-Ray"
  max_session_duration = 3600
  assume_role_policy   = jsonencode(local.newrelic_xray_trust_policy)
  tags                 = { Environment = "shared", Component = "observability" }
}

resource "aws_iam_role_policy" "newrelic_xray" {
  name   = "read-regional-xray"
  role   = aws_iam_role.newrelic_xray.id
  policy = jsonencode(local.newrelic_xray_read_policy)
}
