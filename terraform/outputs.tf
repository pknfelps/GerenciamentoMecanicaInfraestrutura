output "aws_region" {
  description = "Região AWS configurada para a infraestrutura."
  value       = var.aws_region
}

output "cluster_name" {
  description = "Nome do cluster EKS derivado do ambiente."
  value       = local.cluster_name
}

output "vpc_id" {
  description = "ID da VPC criada para o cluster."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas de suporte ao NAT; os nós usam workload_subnet_ids."
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

output "workload_subnet_ids" {
  description = "Subnets privadas em duas AZs para EKS, Lambda e NLB interno."
  value       = aws_subnet.workload[*].id
}

output "database_subnet_ids" {
  description = "Subnets isoladas em duas AZs para o DB subnet group do PostgreSQL."
  value       = aws_subnet.database[*].id
}

output "workload_route_table_id" {
  description = "Tabela de rotas dos workloads: NAT e gateway endpoint S3."
  value       = aws_route_table.workload.id
}

output "database_route_table_id" {
  description = "Tabela do banco sem rota de internet."
  value       = aws_route_table.database.id
}

output "nat_gateway_id" {
  description = "NAT zonal pertencente ao ambiente; remover junto da base no descarte."
  value       = aws_nat_gateway.main.id
}

output "nat_eip_allocation_id" {
  description = "Elastic IP do NAT, gerenciado no mesmo estado do ambiente."
  value       = aws_eip.nat.id
}

output "s3_vpc_endpoint_id" {
  description = "Gateway endpoint S3 dos workloads."
  value       = aws_vpc_endpoint.s3.id
}
