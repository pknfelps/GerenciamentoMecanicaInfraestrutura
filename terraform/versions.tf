terraform {
  required_version = "~> 1.15.0"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.58.0"
    }
  }
}
