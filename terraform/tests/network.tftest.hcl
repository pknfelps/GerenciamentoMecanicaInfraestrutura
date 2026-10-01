# Executado com cada environments/<ambiente>.tfvars; nunca chama a AWS.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "121754142617"
    }
  }


  mock_data "aws_iam_user" {
    defaults = {
      arn = "arn:aws:iam::121754142617:user/mecanica"
    }
  }

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
      aws_eks_cluster.main.access_config[0].authentication_mode == "API_AND_CONFIG_MAP" &&
      aws_eks_cluster.main.access_config[0].bootstrap_cluster_creator_admin_permissions == (var.environment == "hom") &&
      data.aws_iam_user.operator.user_name == "mecanica" &&
      aws_eks_access_entry.operator.type == "STANDARD" &&
      aws_eks_access_entry.operator.principal_arn == "arn:aws:iam::121754142617:user/mecanica" &&
      aws_eks_access_entry.operator.cluster_name == aws_eks_cluster.main.name &&
      aws_eks_access_policy_association.operator_admin.cluster_name == aws_eks_access_entry.operator.cluster_name &&
      aws_eks_access_policy_association.operator_admin.principal_arn == aws_eks_access_entry.operator.principal_arn &&
      aws_eks_access_policy_association.operator_admin.policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" &&
      aws_eks_access_policy_association.operator_admin.access_scope[0].type == "cluster"
    )
    error_message = "O usuário existente mecanica deve receber administração Kubernetes no cluster do ambiente, preservando CONFIG_MAP."
  }

  assert {
    condition = (
      length(aws_eks_access_entry.pipeline) == 3 &&
      alltrue([for component, entry in aws_eks_access_entry.pipeline :
        entry.cluster_name == aws_eks_cluster.main.name && entry.type == "STANDARD" &&
        entry.principal_arn == "arn:aws:iam::121754142617:role/mecanica/pipelines/mecanica-${var.environment}-${component}-github"
      ]) &&
      aws_eks_access_policy_association.pipeline["base"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" &&
      aws_eks_access_policy_association.pipeline["base"].access_scope[0].type == "cluster" &&
      alltrue([for component in ["api", "database"] :
        aws_eks_access_policy_association.pipeline[component].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy" &&
        aws_eks_access_policy_association.pipeline[component].access_scope[0].type == "namespace" &&
        toset(aws_eks_access_policy_association.pipeline[component].access_scope[0].namespaces) == toset(["default"])
      ])
    )
    error_message = "Base administra somente seu cluster; API/banco editam somente default no próprio ambiente."
  }

  assert {
    condition = (
      var.kubernetes_version == "1.36" &&
      aws_eks_cluster.main.version == var.kubernetes_version &&
      aws_eks_node_group.main.version == aws_eks_cluster.main.version
    )
    error_message = "hom e prd devem fixar Kubernetes 1.36 e manter o node group na mesma versão do cluster."
  }

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
      toset(aws_eks_node_group.main.instance_types) == toset(["t3.small"]) &&
      aws_eks_node_group.main.capacity_type == "ON_DEMAND" &&
      aws_eks_node_group.main.scaling_config[0].min_size == 1 &&
      aws_eks_node_group.main.scaling_config[0].desired_size == 1 &&
      aws_eks_node_group.main.scaling_config[0].max_size == 1 &&
      output.workload_subnet_ids == aws_subnet.workload[*].id &&
      output.database_subnet_ids == aws_subnet.database[*].id
    )
    error_message = "Capacidade deve ser um t3.small On-Demand; outputs devem identificar as subnets corretas."
  }
}
