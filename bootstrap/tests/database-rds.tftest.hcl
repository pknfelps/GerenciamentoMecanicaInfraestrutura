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

run "database_roles_can_manage_only_own_postgres" {
  command = plan

  assert {
    condition     = aws_iam_service_linked_role.rds.aws_service_name == "rds.amazonaws.com"
    error_message = "O bootstrap deve manter a service-linked role do RDS."
  }

  assert {
    condition = alltrue([for environment in local.environments :
      aws_iam_role_policy.database_rds[environment].role == aws_iam_role.pipeline["${environment}-database"].name &&
      aws_iam_role_policy.database_network[environment].role == aws_iam_role.pipeline["${environment}-database"].name &&
      local.database_rds_arns[environment].instance == "arn:aws:rds:us-east-1:121754142617:db:mecanica-${environment}-postgres" &&
      local.database_rds_arns[environment].subgrp == "arn:aws:rds:us-east-1:121754142617:subgrp:mecanica-${environment}-database" &&
      one([for statement in jsondecode(aws_iam_role_policy.database_rds[environment].policy).Statement : statement if statement.Sid == "CreateTaggedPostgres"]).Resource == [local.database_rds_arns[environment].instance] &&
      one([for statement in jsondecode(aws_iam_role_policy.database_rds[environment].policy).Statement : statement if statement.Sid == "UseOwnSubnetGroupForPostgres"]).Resource == [local.database_rds_arns[environment].subgrp] &&
      toset(one([for statement in jsondecode(aws_iam_role_policy.database_rds[environment].policy).Statement : statement if statement.Sid == "ManageOwnPostgres"]).Resource) == toset(values(local.database_rds_arns[environment])) &&
      alltrue([for statement in jsondecode(aws_iam_role_policy.database_rds[environment].policy).Statement :
        !contains(flatten([statement.Action]), "rds:CreateDBCluster") &&
        !contains(flatten([statement.Action]), "rds:DeleteDBCluster") &&
        !contains(flatten([statement.Action]), "secretsmanager:GetSecretValue") &&
        !contains(flatten([statement.Action]), "iam:PassRole")
      ])
    ])
    error_message = "Cada role database deve usar apenas seus recursos PostgreSQL, sem Aurora, leitura de secrets ou PassRole."
  }

  assert {
    condition = alltrue([for environment in local.environments :
      length(jsondecode(aws_iam_role_policy.database_rds[environment].policy).Statement) == 9 &&
      length(jsondecode(aws_iam_role_policy.database_network[environment].policy).Statement) == 6 &&
      one([for statement in jsondecode(aws_iam_role_policy.database_rds[environment].policy).Statement : statement if statement.Sid == "CreateTaggedPostgres"]).Condition.Bool == {
        "rds:ManageMasterUserPassword" = "true"
        "rds:PubliclyAccessible"       = "false"
        "rds:StorageEncrypted"         = "true"
      } &&
      one([for statement in jsondecode(aws_iam_role_policy.database_rds[environment].policy).Statement : statement if statement.Sid == "PrepareRdsManagedSecret"]).Resource == [local.database_rds_secret_arn] &&
      toset(one([for statement in jsondecode(aws_iam_role_policy.database_rds[environment].policy).Statement : statement if statement.Sid == "PrepareRdsManagedSecret"]).Action) == toset(["secretsmanager:CreateSecret", "secretsmanager:TagResource"]) &&
      one([for statement in jsondecode(aws_iam_role_policy.database_network[environment].policy).Statement : statement if statement.Sid == "CreateTaggedPostgresGroup"]).Condition.StringEquals["aws:RequestTag/Name"] == "mecanica-${environment}-postgres" &&
      alltrue([for statement in jsondecode(aws_iam_role_policy.database_network[environment].policy).Statement :
        !contains(flatten([statement.Action]), "ec2:AuthorizeSecurityGroupEgress") &&
        (!contains(flatten([statement.Action]), "ec2:RevokeSecurityGroupIngress") || statement.Sid == "ManageOwnPostgresGroup")
      ]) &&
      length(aws_iam_role_policy.database_rds[environment].policy) < 10240 &&
      length(aws_iam_role_policy.database_network[environment].policy) < 10240
    ])
    error_message = "As policies devem exigir segredo RDS, rede privada, criptografia e caber no limite inline."
  }
}
