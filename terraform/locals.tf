locals {
  name_prefix  = "mecanica-${var.environment}"
  cluster_name = "${local.name_prefix}-eks"

  # As tags de identificação não podem ser sobrescritas por tags adicionais.
  common_tags = merge(var.tags, {
    Project     = "mecanica"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

locals {
  # Uma subnet por AZ em cada camada. Índices distintos evitam sobreposição.
  public_subnet_cidrs   = [for index in [1, 2] : cidrsubnet(var.vpc_cidr, 8, index)]
  workload_subnet_cidrs = [for index in [11, 12] : cidrsubnet(var.vpc_cidr, 8, index)]
  database_subnet_cidrs = [for index in [21, 22] : cidrsubnet(var.vpc_cidr, 8, index)]
}
