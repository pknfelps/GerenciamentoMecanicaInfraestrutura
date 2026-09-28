variable "environment" {
  description = "Ambiente de implantação: hom ou prd."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["hom", "prd"], var.environment)
    error_message = "O ambiente deve ser hom ou prd."
  }
}

variable "aws_region" {
  description = "Região AWS onde a infraestrutura será criada."
  type        = string
  default     = "us-east-1"
}

variable "kubernetes_version" {
  description = "Versão minor explícita do Kubernetes para o cluster EKS e seu Managed Node Group."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^1[.][0-9]+$", var.kubernetes_version))
    error_message = "Informe a versão minor do Kubernetes no formato 1.N, como 1.36."
  }
}

variable "vpc_cidr" {
  description = "Rede IPv4 /16 do ambiente; seis subnets /24 são derivadas sem sobreposição."
  type        = string
  nullable    = false

  validation {
    condition = can(cidrnetmask(var.vpc_cidr)) && try(
      split("/", var.vpc_cidr)[1] == "16" && cidrhost(var.vpc_cidr, 0) == split("/", var.vpc_cidr)[0], false
    )
    error_message = "Informe uma rede IPv4 /16 canônica, como 10.0.0.0/16."
  }
}

variable "node_instance_types" {
  description = "Tipos de instância EC2 permitidos no Managed Node Group."
  type        = list(string)
  default     = ["t3.medium"]
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
  default     = 1

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size deve ser maior ou igual a 1."
  }
}

variable "node_max_size" {
  description = "Quantidade máxima de nós do Managed Node Group."
  type        = number
  default     = 1

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size deve ser maior ou igual a 1."
  }
}

variable "tags" {
  description = "Tags adicionais aplicadas aos recursos AWS. Project, Environment e ManagedBy são definidos pela infraestrutura e têm precedência."
  type        = map(string)
  default     = {}
}
