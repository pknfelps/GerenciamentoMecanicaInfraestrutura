resource "aws_security_group" "auth" {
  name        = "${local.name_prefix}-auth"
  description = "Origem da funcao de autenticacao do ambiente"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-auth" }
}

locals {
  configuration = {
    "jwt-secret-arn"         = aws_secretsmanager_secret.jwt.arn
    "jwt-issuer"             = "${local.name_prefix}-auth"
    "jwt-audience"           = "${local.name_prefix}-api"
    "vpc-id"                 = aws_vpc.main.id
    "workload-subnet-ids"    = jsonencode(aws_subnet.workload[*].id)
    "database-subnet-ids"    = jsonencode(aws_subnet.database[*].id)
    "cluster-name"           = aws_eks_cluster.main.name
    "cluster-arn"            = aws_eks_cluster.main.arn
    "namespace"              = "default"
    "init-namespace"         = "database-init"
    "api-security-group-id"  = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
    "auth-security-group-id" = aws_security_group.auth.id
    "init-security-group-id" = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
    "api-service-name"       = "svc-gerenciamento-api"
    "api-service-port"       = "80"
    "nlb-listener-protocol"  = aws_lb_listener.api.protocol
    "api-integration-uri"    = "http://${aws_lb.api.dns_name}:80"
    "nlb-arn"                = aws_lb.api.arn
    "nlb-dns-name"           = aws_lb.api.dns_name
    "nlb-security-group-id"  = aws_security_group.nlb.id
    "nlb-target-group-arn"   = aws_lb_target_group.api.arn
    "nlb-listener-port"      = "80"
    "api-node-port"          = "30080"
    "ecr-repository-url"     = "121754142617.dkr.ecr.${var.aws_region}.amazonaws.com/mecanica/api"
  }
}

resource "aws_ssm_parameter" "configuration" {
  for_each = local.configuration
  name     = "/mecanica/${var.environment}/base/v2/${each.key}"
  type     = "String"
  value    = each.value
}

output "configuration_parameters" {
  value = { for field, parameter in aws_ssm_parameter.configuration : field => parameter.name }
}
