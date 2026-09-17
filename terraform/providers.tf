provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project   = var.cluster_name
        ManagedBy = "Terraform"
      },
      var.tags
    )
  }
}

