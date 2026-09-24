# Copiar para backend.s3.tf somente APÓS a primeira criação do bucket.
terraform {
  backend "s3" {}
}