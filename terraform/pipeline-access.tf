# As roles pertencem ao bootstrap. Aqui são gerenciadas somente as autorizações EKS.
data "aws_caller_identity" "current" {}

locals {
  pipeline_access = {
    base = {
      policy = "AmazonEKSClusterAdminPolicy"
      scope  = "cluster"
    }
    api = {
      policy = "AmazonEKSEditPolicy"
      scope  = "namespace"
    }
    database = {
      policy = "AmazonEKSEditPolicy"
      scope  = "namespace"
    }
  }
}

resource "aws_eks_access_entry" "pipeline" {
  for_each      = local.pipeline_access
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/mecanica/pipelines/mecanica-${var.environment}-${each.key}-github"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "pipeline" {
  for_each      = local.pipeline_access
  cluster_name  = aws_eks_access_entry.pipeline[each.key].cluster_name
  principal_arn = aws_eks_access_entry.pipeline[each.key].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/${each.value.policy}"

  access_scope {
    type       = each.value.scope
    namespaces = each.value.scope == "namespace" ? (each.key == "database" ? ["database-init"] : ["default"]) : null
  }
}
