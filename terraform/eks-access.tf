# Usuário preexistente: a base administra apenas seu acesso Kubernetes.
data "aws_iam_user" "operator" {
  user_name = "mecanica"
}

resource "aws_eks_access_entry" "operator" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_iam_user.operator.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "operator_admin" {
  cluster_name  = aws_eks_access_entry.operator.cluster_name
  principal_arn = aws_eks_access_entry.operator.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
