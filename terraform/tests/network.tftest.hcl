# Executado com cada environments/<ambiente>.tfvars; nunca chama a AWS.
mock_provider "aws" {


  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::121754142617:role/mock-role"
    }
  }
}

run "private_network_and_single_node" {
  # Apply apenas no provider simulado: resolve IDs para conferir rotas e vínculos.
  command = apply

  assert {
    condition = (
      aws_vpc.main.cidr_block == (var.environment == "hom" ? "10.0.0.0/16" : "10.1.0.0/16") &&
      aws_eks_cluster.main.name == "mecanica-${var.environment}-eks"
    )
    error_message = "O arquivo do ambiente deve selecionar sua VPC e cluster próprios."
  }
  assert {
    condition = (
      length(aws_subnet.public) == 2 && length(aws_subnet.workload) == 2 && length(aws_subnet.database) == 2 &&
      length(distinct(concat(aws_subnet.public[*].cidr_block, aws_subnet.workload[*].cidr_block, aws_subnet.database[*].cidr_block))) == 6 &&
      length(distinct(aws_subnet.workload[*].availability_zone)) == 2 &&
      length(distinct(aws_subnet.database[*].availability_zone)) == 2 &&
      length(distinct(aws_subnet.public[*].availability_zone)) == 2 &&
      alltrue([for subnet in concat(aws_subnet.public, aws_subnet.workload, aws_subnet.database) : !subnet.map_public_ip_on_launch])
    )
    error_message = "Cada camada deve ter duas subnets /24 distintas em duas AZs, sem IP público automático."
  }
  assert {
    condition = (
      toset(aws_eks_cluster.main.vpc_config[0].subnet_ids) == toset(aws_subnet.workload[*].id) &&
      toset(aws_eks_node_group.main.subnet_ids) == toset(aws_subnet.workload[*].id) &&
      aws_eks_cluster.main.vpc_config[0].endpoint_private_access &&
      aws_eks_cluster.main.vpc_config[0].endpoint_public_access &&
      alltrue([for subnet in aws_subnet.workload : subnet.tags["kubernetes.io/role/internal-elb"] == "1"])
    )
    error_message = "EKS deve usar somente workloads privados, endpoint interno e endpoint administrativo público."
  }
  assert {
    condition = (
      aws_nat_gateway.main.subnet_id == aws_subnet.public[0].id &&
      aws_nat_gateway.main.allocation_id == aws_eip.nat.id &&
      aws_nat_gateway.main.connectivity_type == "public" && aws_eip.nat.domain == "vpc" &&
      length(aws_route_table.public.route) == 1 &&
      one(aws_route_table.public.route).gateway_id == aws_internet_gateway.main.id &&
      one(aws_route_table.public.route).cidr_block == "0.0.0.0/0" &&
      length(aws_route_table.workload.route) == 1 &&
      one(aws_route_table.workload.route).nat_gateway_id == aws_nat_gateway.main.id &&
      one(aws_route_table.workload.route).cidr_block == "0.0.0.0/0" &&
      length(aws_route_table.database.route) == 0
    )
    error_message = "Workloads devem sair pelo NAT público único; banco não pode ter rota de internet."
  }
  assert {
    condition = (
      alltrue([for index, association in aws_route_table_association.public : association.subnet_id == aws_subnet.public[index].id && association.route_table_id == aws_route_table.public.id]) &&
      alltrue([for index, association in aws_route_table_association.workload : association.subnet_id == aws_subnet.workload[index].id && association.route_table_id == aws_route_table.workload.id]) &&
      alltrue([for index, association in aws_route_table_association.database : association.subnet_id == aws_subnet.database[index].id && association.route_table_id == aws_route_table.database.id]) &&
      aws_vpc_endpoint.s3.vpc_id == aws_vpc.main.id &&
      aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" &&
      aws_vpc_endpoint.s3.service_name == "com.amazonaws.us-east-1.s3" &&
      toset(aws_vpc_endpoint.s3.route_table_ids) == toset([aws_route_table.workload.id])
    )
    error_message = "Cada camada deve usar sua tabela; somente workloads recebem o endpoint S3."
  }
  assert {
    condition = (
      toset(aws_eks_node_group.main.instance_types) == toset(["t3.medium"]) &&
      aws_eks_node_group.main.capacity_type == "ON_DEMAND" &&
      aws_eks_node_group.main.scaling_config[0].min_size == 1 &&
      aws_eks_node_group.main.scaling_config[0].desired_size == 1 &&
      aws_eks_node_group.main.scaling_config[0].max_size == 1 &&
      output.workload_subnet_ids == aws_subnet.workload[*].id &&
      output.database_subnet_ids == aws_subnet.database[*].id
    )
    error_message = "Capacidade deve ser um t3.medium On-Demand; outputs devem identificar as subnets corretas."
  }
}
