mock_provider "aws" {}

variables {
  aws_account_id = "121754142617"
  github_subject_prefixes = {
    api      = "repo:pknfelps/GerenciamentoMecanicaSistema"
    infra    = "repo:pknfelps/GerenciamentoMecanicaInfraestrutura"
    database = "repo:pknfelps/GerenciamentoMecanicaBancoDados"
    auth     = "repo:pknfelps/GerenciamentoMecanicaAutenticacao"
  }
}

run "database_consumer_read_only" {
  command = plan
  assert {
    condition = alltrue([for environment in local.environments :
      jsondecode(aws_iam_role_policy.database_metadata_read[environment].policy) == {
        Version = "2012-10-17"
        Statement = [{
          Sid       = "VerifyBaseNetwork"
          Effect    = "Allow"
          Action    = ["ec2:DescribeVpcs", "ec2:DescribeSubnets", "ec2:DescribeRouteTables", "ec2:DescribeSecurityGroups"]
          Resource  = "*"
          Condition = { StringEquals = { "aws:RequestedRegion" = "us-east-1" } }
        }]
      } &&
      aws_iam_role_policy.database_metadata_read[environment].role == aws_iam_role.pipeline["${environment}-database"].name &&
      length(aws_iam_role_policy.database_metadata_read[environment].policy) +
      length(aws_iam_role_policy.workload_eks["${environment}-database"].policy) +
      length(jsonencode(local.pipeline_policies["${environment}-database"])) < 10240
    ])
    error_message = "A role database deve receber somente as quatro consultas EC2 em us-east-1, dentro da quota inline."
  }
}
