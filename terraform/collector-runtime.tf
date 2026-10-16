data "aws_secretsmanager_secret" "newrelic" {
  name = "/mecanica/${var.environment}/observability/newrelic-license-key"
}

resource "aws_iam_role" "collector_runtime" {
  name        = "${local.name_prefix}-collector-runtime"
  description = "Collector: leitura da License Key New Relic via EKS Pod Identity"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = { StringEquals = {
        "aws:RequestTag/eks-cluster-arn"            = aws_eks_cluster.main.arn
        "aws:RequestTag/kubernetes-namespace"       = "observability"
        "aws:RequestTag/kubernetes-service-account" = "otel-collector"
      } }
    }]
  })
}

resource "aws_iam_role_policy" "collector_newrelic" {
  name = "read-newrelic-license-key"
  role = aws_iam_role.collector_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = data.aws_secretsmanager_secret.newrelic.arn
    }]
  })
}

resource "aws_eks_pod_identity_association" "collector" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "observability"
  service_account = "otel-collector"
  role_arn        = aws_iam_role.collector_runtime.arn
  depends_on      = [aws_eks_addon.pod_identity_agent, aws_iam_role_policy.collector_newrelic]
}
