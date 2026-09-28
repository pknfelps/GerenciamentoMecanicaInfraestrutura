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
