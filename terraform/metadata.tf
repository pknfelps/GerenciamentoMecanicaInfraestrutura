# Identidade durável da criação da base. Não depende da existência de parâmetros SSM.
resource "terraform_data" "generation" {
  input = {
    environment = var.environment
    vpc_id      = aws_vpc.main.id
  }
  triggers_replace = [aws_vpc.main.id]
}

# Reservado à Lambda; o banco será dono das regras de entrada do Aurora.
# Sem ingress/egress neste bloco: as regras específicas serão adicionadas na E2.12.
resource "aws_security_group" "auth" {
  name        = "${local.name_prefix}-auth"
  description = "Origem da funcao de autenticacao do ambiente"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-auth" }
}

output "base_generation" {
  description = "UUID persistente desta criacao da base."
  value       = terraform_data.generation.id
}

output "database_exports" {
  description = "Campos nao secretos do perfil database; prontidao depende dos checks da pipeline."
  value = {
    "vpc-id"                 = aws_vpc.main.id
    "workload-subnet-ids"    = aws_subnet.workload[*].id
    "database-subnet-ids"    = aws_subnet.database[*].id
    "cluster-name"           = aws_eks_cluster.main.name
    "cluster-arn"            = aws_eks_cluster.main.arn
    "namespace"              = "default"
    "api-security-group-id"  = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
    "auth-security-group-id" = aws_security_group.auth.id
    "init-security-group-id" = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  }
}
