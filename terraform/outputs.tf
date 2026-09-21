output "aws_region" {
  description = "Região AWS configurada para a infraestrutura."
  value       = var.aws_region
}

output "cluster_name" {
  description = "Nome definido para o cluster EKS."
  value       = var.cluster_name
}

output "vpc_id" {
  description = "ID da VPC criada para o cluster."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas usadas pelo cluster."
  value       = aws_subnet.public[*].id
}

output "public_subnet_availability_zones" {
  description = "Zonas de disponibilidade das subnets publicas."
  value       = aws_subnet.public[*].availability_zone
}

output "public_route_table_id" {
  description = "ID da tabela de rotas das subnets publicas."
  value       = aws_route_table.public.id
}

output "eks_cluster_role_arn" {
  description = "ARN da role IAM usada pelo control plane do EKS."
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "ARN da role IAM usada pelos nos do EKS."
  value       = aws_iam_role.eks_nodes.arn
}

output "eks_ebs_csi_role_arn" {
  description = "ARN da role IAM usada pelo add-on EBS CSI."
  value       = aws_iam_role.ebs_csi.arn
}

output "eks_cluster_arn" {
  description = "ARN do cluster EKS."
  value       = aws_eks_cluster.main.arn
}

output "eks_cluster_endpoint" {
  description = "Endpoint da API Kubernetes do cluster EKS."
  value       = aws_eks_cluster.main.endpoint
}

output "eks_node_group_name" {
  description = "Nome do Managed Node Group do EKS."
  value       = aws_eks_node_group.main.node_group_name
}
