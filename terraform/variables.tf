variable "aws_region" {
  description = "Região AWS onde a infraestrutura será criada."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Nome do cluster EKS. Deve permanecer alinhado com a pipeline de deploy."
  type        = string
  default     = "api-cluster"
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes usada pelo EKS. Quando nula, a AWS seleciona a versão padrão disponível."
  type        = string
  default     = null
  nullable    = true
}

variable "vpc_cidr" {
  description = "Bloco CIDR IPv4 reservado para a VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Blocos CIDR das duas subnets públicas do cluster."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Informe exatamente dois blocos CIDR para as subnets públicas."
  }
}

variable "node_instance_types" {
  description = "Tipos de instância EC2 permitidos no Managed Node Group."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_capacity_type" {
  description = "Modelo de capacidade dos nós: ON_DEMAND ou SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type deve ser ON_DEMAND ou SPOT."
  }
}

variable "node_min_size" {
  description = "Quantidade mínima de nós do Managed Node Group."
  type        = number
  default     = 1

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size deve ser maior ou igual a 1."
  }
}

variable "node_desired_size" {
  description = "Quantidade desejada de nós do Managed Node Group."
  type        = number
  default     = 2

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size deve ser maior ou igual a 1."
  }
}

variable "node_max_size" {
  description = "Quantidade máxima de nós do Managed Node Group."
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size deve ser maior ou igual a 1."
  }
}

variable "tags" {
  description = "Tags adicionais aplicadas aos recursos AWS."
  type        = map(string)
  default     = {}
}

