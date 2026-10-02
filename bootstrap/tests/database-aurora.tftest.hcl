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

run "database_roles_can_manage_only_own_aurora" {
  command = plan
  assert {
    condition     = aws_iam_service_linked_role.rds.aws_service_name == "rds.amazonaws.com"
    error_message = "O bootstrap deve preparar a service-linked role do RDS antes da pipeline."
  }
  assert {
    condition = alltrue([for environment in local.environments :
      aws_iam_role_policy.database_aurora_rds[environment].role == aws_iam_role.pipeline["${environment}-database"].name &&
      aws_iam_role_policy.database_aurora_network[environment].role == aws_iam_role.pipeline["${environment}-database"].name &&
      toset(flatten([for statement in jsondecode(aws_iam_role_policy.database_aurora_rds[environment].policy).Statement :
        flatten([statement.Resource]) if statement.Resource != "*"
      ])) == toset(values(local.database_aurora_arns[environment])) &&
      alltrue([for statement in jsondecode(aws_iam_role_policy.database_aurora_rds[environment].policy).Statement :
        !contains(flatten([statement.Action]), "secretsmanager:GetSecretValue") &&
        !contains(flatten([statement.Action]), "iam:PassRole")
      ])
    ])
    error_message = "Cada role database deve administrar apenas seus ARNs Aurora e não receber leitura de secrets nem PassRole."
  }

  assert {
    condition = alltrue([for environment in local.environments :
      length(jsondecode(aws_iam_role_policy.database_aurora_rds[environment].policy).Statement) == 5 &&
      length(jsondecode(aws_iam_role_policy.database_aurora_network[environment].policy).Statement) == 6 &&
      alltrue([for statement in jsondecode(aws_iam_role_policy.database_aurora_network[environment].policy).Statement :
        !contains(flatten([statement.Action]), "ec2:AuthorizeSecurityGroupEgress") &&
        (!contains(flatten([statement.Action]), "ec2:RevokeSecurityGroupIngress") || statement.Sid == "ManageOwnAuroraGroup")
      ]) &&
      length(aws_iam_role_policy.database_aurora_rds[environment].policy) < 10240 &&
      length(aws_iam_role_policy.database_aurora_network[environment].policy) < 10240
    ])
    error_message = "As policies devem manter o limite inline, sem autorização de egress ou revogação de outros SGs."
  }
}
