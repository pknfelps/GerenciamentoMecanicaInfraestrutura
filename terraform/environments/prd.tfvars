# Somente parâmetros públicos; secrets nunca pertencem a este arquivo.
environment         = "prd"
aws_region          = "us-east-1"
vpc_cidr            = "10.1.0.0/16"
node_instance_types = ["t3.medium"]
node_capacity_type  = "ON_DEMAND"
node_min_size       = 1
node_desired_size   = 1
node_max_size       = 1
